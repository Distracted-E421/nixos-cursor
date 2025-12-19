//! Protobuf message definitions for Cursor API
//!
//! These are manually defined based on API reverse engineering.
//! The Cursor API uses Connect Protocol with protobuf serialization.

use prost::Message;

/// Chat request message
/// Based on reverse-engineered schema from proxy captures
#[derive(Clone, Message)]
pub struct ChatRequest {
    /// Conversation messages
    #[prost(message, repeated, tag = "1")]
    pub messages: Vec<ChatMessage>,
    
    /// Model name (e.g., "claude-4.5-sonnet")
    #[prost(string, tag = "2")]
    pub model: String,
    
    /// Conversation ID (UUID)
    #[prost(string, optional, tag = "3")]
    pub conversation_id: Option<String>,
    
    /// Whether to stream response
    #[prost(bool, tag = "4")]
    pub stream: bool,
    
    /// Tool definitions
    #[prost(message, repeated, tag = "5")]
    pub tools: Vec<ToolDefinition>,
    
    /// File context
    #[prost(message, repeated, tag = "6")]
    pub files: Vec<FileContext>,
    
    /// Max tokens
    #[prost(int32, optional, tag = "7")]
    pub max_tokens: Option<i32>,
}

/// Chat message
#[derive(Clone, Message)]
pub struct ChatMessage {
    /// Message text content
    #[prost(string, tag = "1")]
    pub content: String,
    
    /// Role: 1 = user, 2 = assistant, 3 = system
    #[prost(int32, tag = "2")]
    pub role: i32,
    
    /// Message ID (UUID)
    #[prost(string, optional, tag = "13")]
    pub message_id: Option<String>,
    
    /// Tool call (if this is an assistant message with tool use)
    #[prost(message, optional, tag = "18")]
    pub tool_call: Option<ToolCall>,
}

/// File context attachment
#[derive(Clone, Message)]
pub struct FileContext {
    /// File path
    #[prost(string, tag = "1")]
    pub path: String,
    
    /// File status: 1 = active
    #[prost(int32, tag = "2")]
    pub status: i32,
    
    /// File content
    #[prost(string, tag = "3")]
    pub content: String,
    
    /// File type enum
    #[prost(int32, tag = "6")]
    pub file_type: i32,
    
    /// Whether file is git tracked
    #[prost(bool, tag = "10")]
    pub tracked: bool,
}

/// Tool definition
#[derive(Clone, Message)]
pub struct ToolDefinition {
    /// Tool name
    #[prost(string, tag = "1")]
    pub name: String,
    
    /// Tool description
    #[prost(string, tag = "2")]
    pub description: String,
}

/// Tool call (in response)
#[derive(Clone, Message)]
pub struct ToolCall {
    /// Tool invocation ID
    #[prost(string, tag = "1")]
    pub tool_id: String,
    
    /// Tool name
    #[prost(string, tag = "2")]
    pub tool_name: String,
    
    /// Whether tool call is complete
    #[prost(bool, tag = "3")]
    pub completed: bool,
    
    /// Tool arguments (JSON string)
    #[prost(string, tag = "5")]
    pub arguments: String,
}

/// Chat response (streaming chunk)
#[derive(Clone, Message)]
pub struct ChatResponse {
    /// Response type
    #[prost(int32, tag = "1")]
    pub response_type: i32,
    
    /// Text content (for text chunks)
    #[prost(string, tag = "2")]
    pub content: String,
    
    /// Tool call (for tool invocations)
    #[prost(message, optional, tag = "3")]
    pub tool_call: Option<ToolCall>,
    
    /// Usage stats (for final response)
    #[prost(message, optional, tag = "4")]
    pub usage: Option<UsageStats>,
    
    /// Error message
    #[prost(string, optional, tag = "5")]
    pub error: Option<String>,
}

/// Token usage statistics
#[derive(Clone, Message)]
pub struct UsageStats {
    /// Prompt tokens
    #[prost(int64, tag = "1")]
    pub prompt_tokens: i64,
    
    /// Completion tokens
    #[prost(int64, tag = "2")]
    pub completion_tokens: i64,
}

/// Role enum for messages
pub mod role {
    pub const USER: i32 = 1;
    pub const ASSISTANT: i32 = 2;
    pub const SYSTEM: i32 = 3;
}

/// Response type enum
pub mod response_type {
    pub const TEXT: i32 = 1;
    pub const TOOL_CALL: i32 = 2;
    pub const DONE: i32 = 3;
    pub const ERROR: i32 = 4;
    pub const THINKING: i32 = 5;
}

/// Connect Protocol envelope
pub struct ConnectEnvelope;

impl ConnectEnvelope {
    /// Encode a message with Connect Protocol framing
    /// Format: 1 byte flags + 4 byte length (big endian) + payload
    pub fn encode<M: Message>(message: &M) -> Vec<u8> {
        let payload = message.encode_to_vec();
        let mut envelope = Vec::with_capacity(5 + payload.len());
        
        // Flags byte (0x00 for non-compressed)
        envelope.push(0x00);
        
        // Length as 4 bytes big endian
        let len = payload.len() as u32;
        envelope.extend_from_slice(&len.to_be_bytes());
        
        // Payload
        envelope.extend(payload);
        
        envelope
    }
    
    /// Decode a Connect Protocol envelope
    /// Returns (flags, payload) or error
    pub fn decode(data: &[u8]) -> Result<(u8, Vec<u8>), &'static str> {
        if data.len() < 5 {
            return Err("Envelope too short");
        }
        
        let flags = data[0];
        let len = u32::from_be_bytes([data[1], data[2], data[3], data[4]]) as usize;
        
        if data.len() < 5 + len {
            return Err("Incomplete payload");
        }
        
        Ok((flags, data[5..5+len].to_vec()))
    }
    
    /// Decode a protobuf message from Connect envelope
    pub fn decode_message<M: Message + Default>(data: &[u8]) -> Result<M, &'static str> {
        let (_, payload) = Self::decode(data)?;
        M::decode(payload.as_slice()).map_err(|_| "Failed to decode protobuf")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_envelope_encode() {
        let msg = ChatMessage {
            content: "Hello".to_string(),
            role: role::USER,
            message_id: None,
            tool_call: None,
        };
        
        let envelope = ConnectEnvelope::encode(&msg);
        
        // Should start with 0x00 flags
        assert_eq!(envelope[0], 0x00);
        
        // Length should be correct
        let len = u32::from_be_bytes([envelope[1], envelope[2], envelope[3], envelope[4]]);
        assert_eq!(len as usize, envelope.len() - 5);
    }
    
    #[test]
    fn test_envelope_roundtrip() {
        let msg = ChatMessage {
            content: "Test message".to_string(),
            role: role::ASSISTANT,
            message_id: Some("test-id".to_string()),
            tool_call: None,
        };
        
        let envelope = ConnectEnvelope::encode(&msg);
        let decoded: ChatMessage = ConnectEnvelope::decode_message(&envelope).unwrap();
        
        assert_eq!(decoded.content, msg.content);
        assert_eq!(decoded.role, msg.role);
    }
}

