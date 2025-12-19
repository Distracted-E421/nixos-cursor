//! Request/Response Injection Module
//!
//! Provides hooks for modifying Cursor API traffic:
//! - System prompt injection
//! - Context injection  
//! - Header modification
//! - Version spoofing

use bytes::Bytes;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Injection rules configuration
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InjectionConfig {
    /// Enable injection
    pub enabled: bool,
    /// System prompt to prepend to conversations
    pub system_prompt: Option<String>,
    /// Custom mode name (replaces default)
    pub custom_mode: Option<String>,
    /// Additional context files to inject
    pub context_files: Vec<PathBuf>,
    /// Header overrides
    pub headers: HashMap<String, String>,
    /// Version to spoof (if any)
    pub spoof_version: Option<String>,
    /// Rules file path (for dynamic reloading)
    pub rules_file: Option<PathBuf>,
}

/// Runtime injection state
pub struct InjectionEngine {
    config: Arc<RwLock<InjectionConfig>>,
    /// Cached context content
    context_cache: Arc<RwLock<HashMap<PathBuf, String>>>,
    /// Request modification stats
    modified_requests: std::sync::atomic::AtomicU64,
}

impl InjectionEngine {
    /// Create new injection engine
    pub fn new(config: InjectionConfig) -> Self {
        Self {
            config: Arc::new(RwLock::new(config)),
            context_cache: Arc::new(RwLock::new(HashMap::new())),
            modified_requests: std::sync::atomic::AtomicU64::new(0),
        }
    }
    
    /// Check if injection is enabled
    pub async fn is_enabled(&self) -> bool {
        self.config.read().await.enabled
    }
    
    /// Update configuration
    pub async fn update_config(&self, config: InjectionConfig) {
        *self.config.write().await = config;
        // Clear context cache on config update
        self.context_cache.write().await.clear();
    }
    
    /// Reload config from file
    pub async fn reload_from_file(&self) -> Result<(), String> {
        let path = {
            let config = self.config.read().await;
            config.rules_file.clone()
        };
        
        if let Some(path) = path {
            let content = tokio::fs::read_to_string(&path).await
                .map_err(|e| format!("Failed to read rules file: {}", e))?;
            let config: InjectionConfig = toml::from_str(&content)
                .map_err(|e| format!("Failed to parse rules file: {}", e))?;
            self.update_config(config).await;
            info!("Reloaded injection config from {:?}", path);
        }
        Ok(())
    }
    
    /// Get stats
    pub fn modified_count(&self) -> u64 {
        self.modified_requests.load(std::sync::atomic::Ordering::Relaxed)
    }
    
    /// Modify request headers
    pub async fn modify_headers(&self, headers: &mut http::HeaderMap) {
        let config = self.config.read().await;
        
        if !config.enabled {
            return;
        }
        
        // Apply header overrides
        for (name, value) in &config.headers {
            if let Ok(header_name) = http::header::HeaderName::try_from(name.as_str()) {
                if let Ok(header_value) = http::header::HeaderValue::try_from(value.as_str()) {
                    headers.insert(header_name, header_value);
                    debug!("Injected header: {} = {}", name, value);
                }
            }
        }
        
        // Spoof version if configured
        if let Some(version) = &config.spoof_version {
            if let Ok(header_value) = http::header::HeaderValue::try_from(version.as_str()) {
                headers.insert(
                    http::header::HeaderName::try_from("x-cursor-client-version").unwrap(),
                    header_value,
                );
                debug!("Spoofed version to: {}", version);
            }
        }
    }
    
    /// Modify request body (protobuf) for chat endpoints
    pub async fn modify_chat_request(&self, body: &Bytes, endpoint: &str) -> Option<Bytes> {
        let config = self.config.read().await;
        
        if !config.enabled {
            return None;
        }
        
        // Only modify chat-related endpoints
        if !endpoint.contains("Chat") && !endpoint.contains("Unified") {
            return None;
        }
        
        // Check if we have anything to inject
        if config.system_prompt.is_none() && config.context_files.is_empty() {
            return None;
        }
        
        // Try to parse and modify the protobuf request
        match self.inject_into_request(body, &config).await {
            Ok(modified) => {
                self.modified_requests.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                info!("🔧 Modified chat request (injection #{}) for {}", 
                      self.modified_count(), endpoint);
                Some(modified)
            }
            Err(e) => {
                warn!("Failed to inject into request: {}", e);
                None
            }
        }
    }
    
    /// Internal: Inject system prompt and context into protobuf request
    async fn inject_into_request(&self, body: &Bytes, config: &InjectionConfig) -> Result<Bytes, String> {
        // Connect protocol framing: [1 byte flags][4 bytes length BE][payload]
        if body.len() < 5 {
            return Err("Body too short for Connect framing".to_string());
        }
        
        let flags = body[0];
        let payload_len = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
        
        if body.len() < 5 + payload_len {
            return Err("Incomplete Connect frame".to_string());
        }
        
        let payload = &body[5..5 + payload_len];
        
        // Parse as StreamUnifiedChatRequestWithTools
        // Field 1 = stream_unified_chat_request (message)
        // Inside that, field 1 = conversation (repeated message)
        
        let modified_payload = self.inject_system_message(payload, config).await?;
        
        // Re-frame with Connect protocol
        let mut result = Vec::with_capacity(5 + modified_payload.len());
        result.push(flags);
        result.extend_from_slice(&(modified_payload.len() as u32).to_be_bytes());
        result.extend_from_slice(&modified_payload);
        
        Ok(Bytes::from(result))
    }
    
    /// Inject a system message at the start of conversation
    async fn inject_system_message(&self, payload: &[u8], config: &InjectionConfig) -> Result<Vec<u8>, String> {
        // Build system message to prepend
        let mut system_content = String::new();
        
        // Add system prompt if configured
        if let Some(prompt) = &config.system_prompt {
            system_content.push_str(prompt);
            system_content.push_str("\n\n");
        }
        
        // Add context files
        for path in &config.context_files {
            match tokio::fs::read_to_string(path).await {
                Ok(content) => {
                    system_content.push_str(&format!("--- {} ---\n", path.display()));
                    system_content.push_str(&content);
                    system_content.push_str("\n\n");
                }
                Err(e) => {
                    warn!("Failed to read context file {:?}: {}", path, e);
                }
            }
        }
        
        if system_content.is_empty() {
            return Ok(payload.to_vec());
        }
        
        // Build a ConversationMessage with type=SYSTEM (3)
        let system_msg = encode_conversation_message(&system_content, 3, "system-inject-001");
        
        // Now we need to prepend this to the conversation array in the request
        // This is complex because we need to:
        // 1. Parse field 1 of StreamUnifiedChatRequestWithTools (stream_unified_chat_request)
        // 2. Inside that, prepend to field 1 (conversation repeated)
        
        let modified = prepend_to_conversation(payload, &system_msg)?;
        Ok(modified)
    }
    
    /// Load context files into cache
    pub async fn preload_context(&self) -> Result<(), String> {
        let config = self.config.read().await;
        let mut cache = self.context_cache.write().await;
        
        for path in &config.context_files {
            match tokio::fs::read_to_string(path).await {
                Ok(content) => {
                    cache.insert(path.clone(), content);
                }
                Err(e) => {
                    warn!("Failed to preload {:?}: {}", path, e);
                }
            }
        }
        
        Ok(())
    }
}

/// Encode a ConversationMessage in protobuf wire format
fn encode_conversation_message(text: &str, msg_type: i32, bubble_id: &str) -> Vec<u8> {
    let mut buf = Vec::new();
    
    // Field 1: text (string) - tag = (1 << 3) | 2 = 0x0a
    buf.push(0x0a);
    write_varint(&mut buf, text.len() as u64);
    buf.extend_from_slice(text.as_bytes());
    
    // Field 2: type (int32) - tag = (2 << 3) | 0 = 0x10
    buf.push(0x10);
    write_varint(&mut buf, msg_type as u64);
    
    // Field 13: bubble_id (string) - tag = (13 << 3) | 2 = 0x6a
    buf.push(0x6a);
    write_varint(&mut buf, bubble_id.len() as u64);
    buf.extend_from_slice(bubble_id.as_bytes());
    
    buf
}

/// Write a varint to buffer
fn write_varint(buf: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            buf.push(byte);
            break;
        } else {
            buf.push(byte | 0x80);
        }
    }
}

/// Read a varint from buffer, return (value, bytes_read)
fn read_varint(buf: &[u8]) -> Option<(u64, usize)> {
    let mut value = 0u64;
    let mut shift = 0;
    
    for (i, &byte) in buf.iter().enumerate() {
        value |= ((byte & 0x7f) as u64) << shift;
        if byte & 0x80 == 0 {
            return Some((value, i + 1));
        }
        shift += 7;
        if shift >= 64 {
            return None;
        }
    }
    None
}

/// Prepend a message to the conversation array in StreamUnifiedChatRequestWithTools
fn prepend_to_conversation(payload: &[u8], system_msg: &[u8]) -> Result<Vec<u8>, String> {
    // StreamUnifiedChatRequestWithTools structure:
    // Field 1: stream_unified_chat_request (message)
    //   Field 1: conversation (repeated message)
    
    let mut result = Vec::new();
    let mut pos = 0;
    let mut found_outer = false;
    
    while pos < payload.len() {
        // Read tag
        let (tag_value, tag_len) = read_varint(&payload[pos..])
            .ok_or_else(|| "Failed to read tag".to_string())?;
        
        let field_num = tag_value >> 3;
        let wire_type = tag_value & 0x7;
        
        if field_num == 1 && wire_type == 2 && !found_outer {
            // This is field 1 (stream_unified_chat_request) - LEN type
            found_outer = true;
            
            // Read length
            let (len, len_bytes) = read_varint(&payload[pos + tag_len..])
                .ok_or_else(|| "Failed to read field length".to_string())?;
            
            let inner_start = pos + tag_len + len_bytes;
            let inner_end = inner_start + len as usize;
            
            if inner_end > payload.len() {
                return Err("Inner message extends past payload".to_string());
            }
            
            // Modify the inner message (StreamUnifiedChatRequest)
            let inner_payload = &payload[inner_start..inner_end];
            let modified_inner = prepend_to_inner_conversation(inner_payload, system_msg)?;
            
            // Write modified field 1
            result.push(0x0a); // tag for field 1, wire type 2
            write_varint(&mut result, modified_inner.len() as u64);
            result.extend_from_slice(&modified_inner);
            
            pos = inner_end;
        } else {
            // Copy other fields as-is
            let field_end = skip_field(payload, pos, wire_type as u8)?;
            result.extend_from_slice(&payload[pos..field_end]);
            pos = field_end;
        }
    }
    
    if !found_outer {
        return Err("Did not find stream_unified_chat_request field".to_string());
    }
    
    Ok(result)
}

/// Prepend system message to conversation field in StreamUnifiedChatRequest
fn prepend_to_inner_conversation(payload: &[u8], system_msg: &[u8]) -> Result<Vec<u8>, String> {
    let mut result = Vec::new();
    
    // First, write our system message as field 1 (conversation)
    result.push(0x0a); // tag for field 1, wire type 2
    write_varint(&mut result, system_msg.len() as u64);
    result.extend_from_slice(system_msg);
    
    // Then copy all original fields
    let mut pos = 0;
    while pos < payload.len() {
        let (tag_value, tag_len) = read_varint(&payload[pos..])
            .ok_or_else(|| "Failed to read tag in inner".to_string())?;
        
        let wire_type = (tag_value & 0x7) as u8;
        let field_end = skip_field(payload, pos, wire_type)?;
        
        result.extend_from_slice(&payload[pos..field_end]);
        pos = field_end;
    }
    
    Ok(result)
}

/// Skip a protobuf field and return position after it
fn skip_field(buf: &[u8], pos: usize, wire_type: u8) -> Result<usize, String> {
    let (_, tag_len) = read_varint(&buf[pos..])
        .ok_or_else(|| "Failed to read tag".to_string())?;
    
    let data_start = pos + tag_len;
    
    match wire_type {
        0 => {
            // Varint
            let (_, val_len) = read_varint(&buf[data_start..])
                .ok_or_else(|| "Failed to read varint value".to_string())?;
            Ok(data_start + val_len)
        }
        1 => {
            // 64-bit
            Ok(data_start + 8)
        }
        2 => {
            // Length-delimited
            let (len, len_bytes) = read_varint(&buf[data_start..])
                .ok_or_else(|| "Failed to read length".to_string())?;
            Ok(data_start + len_bytes + len as usize)
        }
        5 => {
            // 32-bit
            Ok(data_start + 4)
        }
        _ => Err(format!("Unknown wire type: {}", wire_type)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_encode_conversation_message() {
        let msg = encode_conversation_message("Hello", 3, "test-id");
        assert!(!msg.is_empty());
        // Should contain "Hello" bytes
        assert!(msg.windows(5).any(|w| w == b"Hello"));
    }
    
    #[test]
    fn test_varint_roundtrip() {
        let mut buf = Vec::new();
        write_varint(&mut buf, 300);
        let (value, _) = read_varint(&buf).unwrap();
        assert_eq!(value, 300);
    }
}

