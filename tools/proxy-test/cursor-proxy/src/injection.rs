//! Request Injection Module - CONTEXT FILE STRATEGY
//!
//! Correctly injects system messages into Cursor AI chat requests by targeting the 
//! nested Protobuf structure and mimicking a Context File entry.
//! Field 1 (UserRequest) -> Field 3 (ConversationHistory) -> Repeated Field 3 (ConversationEntry)
//! Schema:
//!   Field 1: File Name (String)
//!   Field 2: Content (String)
//!   Field 5: Type/Status (Int32) - Use 0

use bytes::Bytes;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Injection configuration
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InjectionConfig {
    pub enabled: bool,
    pub system_prompt: Option<String>,
    pub context_files: Vec<PathBuf>,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    pub spoof_version: Option<String>,
}

pub struct InjectionEngine {
    config: Arc<RwLock<InjectionConfig>>,
    modified_count: std::sync::atomic::AtomicU64,
}

impl InjectionEngine {
    pub fn new(config: InjectionConfig) -> Self {
        Self {
            config: Arc::new(RwLock::new(config)),
            modified_count: std::sync::atomic::AtomicU64::new(0),
        }
    }
    
    pub async fn is_enabled(&self) -> bool {
        self.config.read().await.enabled
    }
    
    pub fn modified_count(&self) -> u64 {
        self.modified_count.load(std::sync::atomic::Ordering::Relaxed)
    }
    
    pub async fn update_config(&self, config: InjectionConfig) {
        *self.config.write().await = config;
    }
    
    pub async fn modify_chat_request(&self, body: &Bytes, endpoint: &str) -> Option<Bytes> {
        let config = self.config.read().await;
        
        if !config.enabled {
            return None;
        }
        
        if !endpoint.contains("Chat") && !endpoint.contains("Unified") {
            return None;
        }
        
        if config.system_prompt.is_none() && config.context_files.is_empty() {
            return None;
        }
        
        // Build system message content
        let mut system_content = String::new();
        
        if let Some(ref prompt) = config.system_prompt {
            system_content.push_str(prompt);
        }
        
        for path in &config.context_files {
            match std::fs::read_to_string(path) {
                Ok(content) => {
                    system_content.push_str(&format!("\n\n--- {} ---\n", path.display()));
                    system_content.push_str(&content);
                }
                Err(e) => {
                    warn!("Failed to read context file {:?}: {}", path, e);
                }
            }
        }
        
        if system_content.is_empty() {
            return None;
        }
        
        match self.inject_into_request(body, &system_content).await {
            Ok(modified) => {
                self.modified_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                info!(
                    "✨ Injected system message (#{}) into {} ({} → {} bytes)",
                    self.modified_count(),
                    endpoint,
                    body.len(),
                    modified.len()
                );
                Some(modified)
            }
            Err(e) => {
                warn!("Injection failed: {}", e);
                None
            }
        }
    }
    
    async fn inject_into_request(&self, body: &Bytes, system_content: &str) -> Result<Bytes, String> {
        // Debug dump before
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
        let _ = std::fs::write(format!("/tmp/cursor-req-{}-before.bin", ts), body.as_ref());

        // Connect framing
        if body.len() < 5 {
            return Err("Body too short".to_string());
        }
        
        let flags = body[0];
        let payload_len = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
        
        if body.len() < 5 + payload_len {
            return Err(format!("Incomplete frame: need {}, have {}", 5 + payload_len, body.len()));
        }
        
        let payload = &body[5..5 + payload_len];
        
        // Decompress if gzipped (flag bit 0)
        let (decompressed, was_compressed) = if flags & 0x01 != 0 {
            (decompress_gzip(payload)?, true)
        } else {
            (payload.to_vec(), false)
        };
        
        info!("📦 Decompressed payload: {} bytes", decompressed.len());
        
        // Inject system message at protobuf level
        let modified_payload = inject_system_message_recursive(&decompressed, system_content)?;
        
        info!("📦 Modified payload: {} bytes", modified_payload.len());
        
        // Recompress if needed
        let final_payload = if was_compressed {
            compress_gzip(&modified_payload)?
        } else {
            modified_payload
        };
        
        // Re-frame
        let mut result = Vec::with_capacity(5 + final_payload.len());
        result.push(flags);
        result.extend_from_slice(&(final_payload.len() as u32).to_be_bytes());
        result.extend_from_slice(&final_payload);
        
        let _ = std::fs::write(format!("/tmp/cursor-req-{}-after.bin", ts), &result);
        
        Ok(Bytes::from(result))
    }
}

/// Recursive injection logic
fn inject_system_message_recursive(data: &[u8], system_content: &str) -> Result<Vec<u8>, String> {
    // Top Level: Parse fields (Level 0)
    let fields = parse_all_fields(data)?;
    
    let mut new_data = Vec::new();
    let mut found_field1 = false;
    
    for field in fields {
        if field.field_num == 1 && field.wire_type == 2 {
            // Found Field 1 (UserRequest). Recursively parse it.
            found_field1 = true;
            let inner_modified = inject_into_user_request(&field.data, system_content)?;
            
            // Write back Field 1 with NEW content
            new_data.push(0x0a); // Field 1 Tag (1 << 3 | 2)
            write_varint(&mut new_data, inner_modified.len() as u64);
            new_data.extend_from_slice(&inner_modified);
        } else {
            // Copy other fields as-is
            new_data.extend_from_slice(&field.raw);
        }
    }
    
    if !found_field1 {
        return Err("Could not find Field 1 (UserRequest) in top-level message".to_string());
    }
    
    Ok(new_data)
}

fn inject_into_user_request(data: &[u8], system_content: &str) -> Result<Vec<u8>, String> {
    // Parse Level 1 fields
    let fields = parse_all_fields(data)?;
    
    let mut new_data = Vec::new();
    let mut found_conversation = false;
    
    for field in fields {
        if field.field_num == 3 && field.wire_type == 2 {
            // Found Field 3 (ConversationHistory Container). Recursively parse it.
            found_conversation = true;
            let inner_modified = inject_into_conversation(&field.data, system_content)?;
            
            // Write back Field 3 with NEW content
            new_data.push(0x1a); // Field 3 Tag (3 << 3 | 2 = 24|2 = 26 = 0x1A)
            write_varint(&mut new_data, inner_modified.len() as u64);
            new_data.extend_from_slice(&inner_modified);
        } else {
            // Copy other fields
            new_data.extend_from_slice(&field.raw);
        }
    }
    
    if !found_conversation {
        return Err("Could not find Field 3 (ConversationHistory) in UserRequest".to_string());
    }
    
    Ok(new_data)
}

fn inject_into_conversation(data: &[u8], system_content: &str) -> Result<Vec<u8>, String> {
    // Create new system entry
    let system_entry_content = create_context_file_entry(system_content);
    
    let mut new_data = Vec::new();
    
    // 1. Write our NEW entry wrapped in Field 3
    new_data.push(0x1a); // Field 3 Tag
    write_varint(&mut new_data, system_entry_content.len() as u64);
    new_data.extend_from_slice(&system_entry_content);
    
    info!("➕ Inserted system context file entry ({} bytes)", system_entry_content.len());
    
    // 2. Append existing content
    new_data.extend_from_slice(data);
    
    Ok(new_data)
}

/// Create an entry that looks like a Context File
fn create_context_file_entry(text: &str) -> Vec<u8> {
    let mut buf = Vec::new();
    
    // Field 1: File Name (string) - Wire Type 2
    let file_name = "system-context.md";
    buf.push(0x0a); // 1 << 3 | 2 = 0x0A
    write_varint(&mut buf, file_name.len() as u64);
    buf.extend_from_slice(file_name.as_bytes());
    
    // Field 2: Content (string) - Wire Type 2
    let content = format!("**System Context**\n\n{}", text);
    buf.push(0x12); // 2 << 3 | 2 = 0x12
    write_varint(&mut buf, content.len() as u64);
    buf.extend_from_slice(content.as_bytes());
    
    // Field 5: Type/Status (int32) - Wire Type 0
    // Observed value 0 in other context files
    buf.push(0x28); // 5 << 3 | 0 = 0x28
    write_varint(&mut buf, 0); 

    // Field 7: Skipped for now (Structure unknown/complex)
    
    buf
}

// ========== Protobuf parsing helpers ==========

#[derive(Clone)]
struct ProtobufField {
    field_num: u64,
    wire_type: u8,
    data: Vec<u8>,    // Just the data portion (for LEN types)
    raw: Vec<u8>,     // Complete field including tag and length
}

fn parse_all_fields(data: &[u8]) -> Result<Vec<ProtobufField>, String> {
    let mut fields = Vec::new();
    let mut pos = 0;
    
    while pos < data.len() {
        let start = pos;
        
        let (tag, tag_len) = read_varint(&data[pos..])
            .ok_or_else(|| format!("Failed to read tag at pos {}", pos))?;
        pos += tag_len;
        
        let field_num = tag >> 3;
        let wire_type = (tag & 0x7) as u8;
        
        let (field_data, field_end) = match wire_type {
            0 => { // Varint
                let (_, val_len) = read_varint(&data[pos..])
                    .ok_or_else(|| "Failed to read varint".to_string())?;
                (Vec::new(), pos + val_len)
            }
            1 => { // 64-bit
                if pos + 8 > data.len() {
                    return Err(format!("Field {} (64-bit) exceeds buffer at pos {}", field_num, pos));
                }
                (Vec::new(), pos + 8)
            }
            2 => { // LEN
                let (len, len_bytes) = read_varint(&data[pos..])
                    .ok_or_else(|| "Failed to read length".to_string())?;
                let len = len as usize;
                let content_start = pos + len_bytes;
                let content_end = content_start + len;
                
                if content_end > data.len() {
                    return Err(format!("Field {} length {} exceeds buffer (ends at {}, len {})", 
                        field_num, len, content_end, data.len()));
                }
                
                let content = data[content_start..content_end].to_vec();
                (content, content_end)
            }
            5 => { // 32-bit
                if pos + 4 > data.len() {
                    return Err(format!("Field {} (32-bit) exceeds buffer at pos {}", field_num, pos));
                }
                (Vec::new(), pos + 4)
            }
            _ => return Err(format!("Unknown wire type {} at pos {}", wire_type, pos)),
        };
        
        fields.push(ProtobufField {
            field_num,
            wire_type,
            data: field_data,
            raw: data[start..field_end].to_vec(),
        });
        
        pos = field_end;
    }
    
    Ok(fields)
}

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

fn read_varint(buf: &[u8]) -> Option<(u64, usize)> {
    if buf.is_empty() {
        return None;
    }
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

fn decompress_gzip(data: &[u8]) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut decoder = flate2::read::GzDecoder::new(data);
    let mut out = Vec::new();
    decoder.read_to_end(&mut out).map_err(|e| format!("gzip error: {}", e))?;
    Ok(out)
}

fn compress_gzip(data: &[u8]) -> Result<Vec<u8>, String> {
    use std::io::Write;
    use flate2::Compression;
    use flate2::write::GzEncoder;
    
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(data).map_err(|e| format!("gzip error: {}", e))?;
    encoder.finish().map_err(|e| format!("gzip error: {}", e))
}

pub fn load_config(path: &std::path::Path) -> Result<InjectionConfig, String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("Failed to read config: {}", e))?;
    toml::from_str(&content).map_err(|e| format!("Failed to parse config: {}", e))
}
