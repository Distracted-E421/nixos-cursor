//! API client for Cursor AI backend

use crate::auth::AuthToken;
use crate::config::Config;
use crate::context::Context;
use crate::error::{AgentError, Result};
use crate::proto::{self, ConnectEnvelope};
use crate::generated; // Auto-generated proto types
use futures::stream::{Stream, StreamExt};
use prost::Message;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::pin::Pin;
use tracing::{debug, warn};

/// Cursor API client
pub struct CursorClient {
    client: Client,
    token: AuthToken,
    base_url: String,
    default_model: String,
    session_id: String,
    client_version: String,
}

/// Model information
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub name: String,
    #[serde(default)]
    pub default_on: bool,
    #[serde(default)]
    pub supports_agent: bool,
    #[serde(default)]
    pub supports_thinking: bool,
    #[serde(default)]
    pub supports_images: bool,
    #[serde(default)]
    pub auto_context_max_tokens: u64,
    #[serde(default)]
    pub client_display_name: Option<String>,
    pub tooltip_data: Option<TooltipData>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TooltipData {
    pub markdown_content: Option<String>,
}

/// Chat request (JSON format, kept for SSE parsing)
#[derive(Debug, Serialize)]
pub struct ChatRequestJson {
    pub messages: Vec<ChatMessageJson>,
    pub model: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<Vec<String>>,
    pub stream: bool,
}

/// Chat message (JSON format, kept for SSE parsing)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessageJson {
    pub role: String,
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<MessageContext>,
}

/// Message context (files, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageContext {
    pub files: Vec<FileContext>,
}

/// File context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileContext {
    pub path: String,
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
}

/// Events from chat stream
#[derive(Debug, Clone)]
pub enum ChatEvent {
    /// Text content
    Text(String),
    /// Tool call requested
    ToolCall { name: String, args: serde_json::Value },
    /// Tool result (from us)
    ToolResult { name: String, result: String },
    /// Stream complete
    Done { usage: Usage },
    /// Thinking/processing indicator
    Thinking,
    /// Error
    Error(String),
}

/// Token usage
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Usage {
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
}

impl CursorClient {
    /// Create a new API client
    pub fn new(token: AuthToken, config: &Config) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(config.api.timeout_secs))
            .build()?;

        Ok(Self {
            client,
            token,
            base_url: config.api.base_url.clone(),
            default_model: config.api.default_model.clone(),
            session_id: uuid::Uuid::new_v4().to_string(),
            client_version: "2.0.77".to_string(),
        })
    }

    /// Get standard headers for Connect Protocol
    fn connect_headers(&self) -> reqwest::header::HeaderMap {
        use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
        let mut headers = HeaderMap::new();
        headers.insert("Authorization", HeaderValue::from_str(&format!("Bearer {}", self.token.value)).unwrap());
        headers.insert("Content-Type", HeaderValue::from_static("application/json"));
        headers.insert("Connect-Protocol-Version", HeaderValue::from_static("1"));
        headers.insert(HeaderName::from_static("x-cursor-client-version"), HeaderValue::from_str(&self.client_version).unwrap());
        headers.insert(HeaderName::from_static("x-cursor-client-type"), HeaderValue::from_static("ide"));
        headers.insert(HeaderName::from_static("x-cursor-streaming"), HeaderValue::from_static("true"));
        headers.insert(HeaderName::from_static("x-session-id"), HeaderValue::from_str(&self.session_id).unwrap());
        headers.insert(HeaderName::from_static("x-request-id"), HeaderValue::from_str(&uuid::Uuid::new_v4().to_string()).unwrap());
        headers
    }

    /// Check if authentication is valid
    pub async fn check_auth(&self) -> Result<()> {
        let url = format!("{}/aiserver.v1.AiService/AvailableModels", self.base_url);
        
        let response = self.client
            .post(&url)
            .headers(self.connect_headers())
            .body("{}")
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(AgentError::ApiRequest {
                status: response.status().as_u16(),
                message: response.text().await.unwrap_or_default(),
            })
        }
    }

    /// Get available models (names only)
    pub async fn available_models(&self) -> Result<Vec<String>> {
        let models = self.available_models_detailed().await?;
        Ok(models.into_iter().map(|m| m.name).collect())
    }

    /// Get available models with full details
    pub async fn available_models_detailed(&self) -> Result<Vec<ModelInfo>> {
        let url = format!("{}/aiserver.v1.AiService/AvailableModels", self.base_url);
        
        let response = self.client
            .post(&url)
            .headers(self.connect_headers())
            .body("{}")
            .send()
            .await?;

        if response.status().is_success() {
            #[derive(Deserialize)]
            struct ModelsResponse {
                models: Vec<ModelInfo>,
            }

            let body: ModelsResponse = response.json().await?;
            Ok(body.models)
        } else {
            Err(AgentError::ApiRequest {
                status: response.status().as_u16(),
                message: response.text().await.unwrap_or_default(),
            })
        }
    }

    /// Get recommended agent models
    pub async fn recommended_agent_models(&self) -> Result<Vec<ModelInfo>> {
        let models = self.available_models_detailed().await?;
        Ok(models.into_iter()
            .filter(|m| m.supports_agent && m.default_on)
            .collect())
    }

    /// Stream a chat completion
    pub async fn stream_chat(
        &self,
        query: &str,
        context: Context,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<ChatEvent>> + Send>>> {
        self.stream_chat_with_model(query, context, &self.default_model).await
    }

    /// Stream a chat completion with specific model
    /// 
    /// NOTE: The Cursor API uses Connect Protocol with binary protobuf encoding.
    /// The exact schema for StreamUnifiedChatWithTools has not been fully reverse-engineered.
    /// This implementation may not work until the schema is properly captured.
    pub async fn stream_chat_with_model(
        &self,
        query: &str,
        context: Context,
        model: &str,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<ChatEvent>> + Send>>> {
        let url = format!(
            "{}/aiserver.v1.ChatService/StreamUnifiedChatWithTools",
            self.base_url
        );

        // Build protobuf request
        let mut proto_files: Vec<proto::FileContext> = Vec::new();
        for f in context.files {
            proto_files.push(proto::FileContext {
                path: f.path,
                status: 1, // active
                content: f.content,
                file_type: 0,
                tracked: false,
            });
        }

        let proto_request = proto::ChatRequest {
            messages: vec![proto::ChatMessage {
                content: query.to_string(),
                role: proto::role::USER,
                message_id: Some(uuid::Uuid::new_v4().to_string()),
                tool_call: None,
            }],
            model: model.to_string(),
            conversation_id: Some(uuid::Uuid::new_v4().to_string()),
            stream: true,
            tools: vec![
                proto::ToolDefinition { name: "read_file".into(), description: "Read a file".into() },
                proto::ToolDefinition { name: "edit_file".into(), description: "Edit a file".into() },
                proto::ToolDefinition { name: "run_command".into(), description: "Run a command".into() },
            ],
            files: proto_files,
            max_tokens: Some(4096),
        };

        // Encode with Connect Protocol envelope
        let body = ConnectEnvelope::encode(&proto_request);
        
        debug!("Sending protobuf chat request to {} ({} bytes)", url, body.len());

        let mut headers = self.connect_headers();
        headers.insert("Content-Type", "application/connect+proto".parse().unwrap());
        headers.insert("Accept", "application/connect+proto".parse().unwrap());

        let response = self.client
            .post(&url)
            .headers(headers)
            .body(body)
            .send()
            .await?;

        // The API returns non-standard status codes, check response
        let status = response.status().as_u16();
        
        // Handle known failure modes
        if status == 464 || status == 415 || !response.status().is_success() {
            let text = response.text().await.unwrap_or_default();
            
            // Return a helpful error for schema issues
            if status == 464 || text.contains("parse binary") || text.contains("premature EOF") {
                warn!("Protobuf schema mismatch - the ChatService schema needs reverse engineering");
                return Err(AgentError::ProtobufSchemaUnknown {
                    endpoint: "StreamUnifiedChatWithTools".to_string(),
                    hint: "The streaming chat endpoint uses a complex protobuf schema that hasn't been fully reverse-engineered. Use Cursor IDE for chat until this is resolved.".to_string(),
                });
            }
            
            return Err(AgentError::ApiRequest {
                status,
                message: text,
            });
        }

        // Parse protobuf streaming response
        let stream = response.bytes_stream();
        let event_stream = Self::parse_connect_stream(stream);

        Ok(Box::pin(event_stream))
    }
    
    /// Parse Connect Protocol streaming response
    fn parse_connect_stream<S>(stream: S) -> impl Stream<Item = Result<ChatEvent>>
    where
        S: Stream<Item = std::result::Result<bytes::Bytes, reqwest::Error>> + Send + 'static,
    {
        let mut buffer: Vec<u8> = Vec::new();
        
        stream.filter_map(move |chunk_result| {
            let events = match chunk_result {
                Ok(chunk) => {
                    buffer.extend_from_slice(&chunk);
                    Self::extract_connect_events(&mut buffer)
                }
                Err(e) => {
                    vec![Err(AgentError::Http(e))]
                }
            };
            
            async move {
                if events.is_empty() {
                    None
                } else {
                    Some(futures::stream::iter(events))
                }
            }
        })
        .flatten()
    }
    
    /// Extract complete Connect Protocol events from buffer
    fn extract_connect_events(buffer: &mut Vec<u8>) -> Vec<Result<ChatEvent>> {
        let mut events = Vec::new();
        
        // Connect Protocol: 1 byte flags + 4 bytes length + payload
        while buffer.len() >= 5 {
            let len = u32::from_be_bytes([buffer[1], buffer[2], buffer[3], buffer[4]]) as usize;
            
            if buffer.len() < 5 + len {
                break; // Need more data
            }
            
            let flags = buffer[0];
            let payload = buffer[5..5+len].to_vec();
            buffer.drain(..5+len);
            
            // Check for end-stream flag (0x02)
            if flags & 0x02 != 0 {
                events.push(Ok(ChatEvent::Done { usage: Usage::default() }));
                continue;
            }
            
            // Try to decode as ChatResponse
            match proto::ChatResponse::decode(payload.as_slice()) {
                Ok(response) => {
                    match response.response_type {
                        proto::response_type::TEXT => {
                            events.push(Ok(ChatEvent::Text(response.content)));
                        }
                        proto::response_type::TOOL_CALL => {
                            if let Some(tc) = response.tool_call {
                                let args: serde_json::Value = serde_json::from_str(&tc.arguments)
                                    .unwrap_or(serde_json::Value::Null);
                                events.push(Ok(ChatEvent::ToolCall {
                                    name: tc.tool_name,
                                    args,
                                }));
                            }
                        }
                        proto::response_type::DONE => {
                            let usage = response.usage.map(|u| Usage {
                                prompt_tokens: u.prompt_tokens as u64,
                                completion_tokens: u.completion_tokens as u64,
                            }).unwrap_or_default();
                            events.push(Ok(ChatEvent::Done { usage }));
                        }
                        proto::response_type::ERROR => {
                            events.push(Ok(ChatEvent::Error(
                                response.error.unwrap_or_else(|| "Unknown error".to_string())
                            )));
                        }
                        proto::response_type::THINKING => {
                            events.push(Ok(ChatEvent::Thinking));
                        }
                        _ => {
                            // Unknown type, try to extract content anyway
                            if !response.content.is_empty() {
                                events.push(Ok(ChatEvent::Text(response.content)));
                            }
                        }
                    }
                }
                Err(e) => {
                    debug!("Failed to decode protobuf response: {:?}", e);
                    // Try to parse as text/error
                    if let Ok(text) = String::from_utf8(payload.clone()) {
                        if text.contains("error") {
                            events.push(Ok(ChatEvent::Error(text)));
                        } else {
                            events.push(Ok(ChatEvent::Text(text)));
                        }
                    }
                }
            }
        }
        
        events
    }

    /// Stream chat using the generated proto types
    /// 
    /// This uses the reverse-engineered schema from proto/aiserver.proto
    pub async fn stream_chat_proto(
        &self,
        query: &str,
        context: Context,
        model: &str,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<ChatEvent>> + Send>>> {
        let url = format!(
            "{}/aiserver.v1.ChatService/StreamUnifiedChatWithToolsSSE",
            self.base_url
        );

        // Build the request using generated proto types
        let user_message = generated::ConversationMessage {
            text: query.to_string(),
            r#type: generated::conversation_message::MessageType::User as i32,
            bubble_id: uuid::Uuid::new_v4().to_string(),
            attached_code_chunks: context.files.iter().map(|f| {
                generated::conversation_message::CodeChunk {
                    file_path: f.path.clone(),
                    content: f.content.clone(),
                    language_id: f.language.clone().unwrap_or_default(),
                    start_line: 0,
                    end_line: f.content.lines().count() as i32,
                    git_context: None,
                }
            }).collect(),
            ..Default::default()
        };

        let chat_request = generated::StreamUnifiedChatRequest {
            conversation: vec![user_message],
            model_details: Some(generated::ModelDetails {
                model_name: model.to_string(),
                supports_tools: true,
                supports_images: true,
                ..Default::default()
            }),
            is_chat: true,
            conversation_id: uuid::Uuid::new_v4().to_string(),
            allow_long_file_scan: true,
            should_cache: true,
            ..Default::default()
        };

        let request_with_tools = generated::StreamUnifiedChatRequestWithTools {
            stream_unified_chat_request: Some(chat_request),
            client_side_tool_v2_result: None,
        };

        // Encode to protobuf
        let mut buf = Vec::new();
        request_with_tools.encode(&mut buf)?;
        
        // gRPC-web framing: [1 byte flags][4 bytes length BE][payload]
        let mut framed = Vec::with_capacity(5 + buf.len());
        framed.push(0x00); // Data frame (not compressed)
        framed.extend_from_slice(&(buf.len() as u32).to_be_bytes());
        framed.extend_from_slice(&buf);

        debug!("Sending chat request ({} bytes payload, {} bytes framed)", buf.len(), framed.len());

        let mut headers = self.connect_headers();
        headers.insert("Content-Type", "application/grpc-web+proto".parse().unwrap());
        headers.insert("Accept", "application/grpc-web+proto".parse().unwrap());

        let response = self.client
            .post(&url)
            .headers(headers)
            .body(framed)
            .send()
            .await?;

        let status = response.status().as_u16();
        if !response.status().is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(AgentError::ApiRequest { status, message: text });
        }

        // Parse streaming protobuf response
        let stream = response.bytes_stream();
        let event_stream = Self::parse_grpc_web_stream(stream);

        Ok(Box::pin(event_stream))
    }

    /// Parse gRPC-web streaming response using generated types
    fn parse_grpc_web_stream<S>(stream: S) -> impl Stream<Item = Result<ChatEvent>>
    where
        S: Stream<Item = std::result::Result<bytes::Bytes, reqwest::Error>> + Send + 'static,
    {
        let mut buffer: Vec<u8> = Vec::new();
        
        stream.filter_map(move |chunk_result| {
            let events = match chunk_result {
                Ok(chunk) => {
                    buffer.extend_from_slice(&chunk);
                    Self::extract_grpc_web_events(&mut buffer)
                }
                Err(e) => {
                    vec![Err(AgentError::Http(e))]
                }
            };
            
            async move {
                if events.is_empty() {
                    None
                } else {
                    Some(futures::stream::iter(events))
                }
            }
        })
        .flatten()
    }

    /// Extract gRPC-web events from buffer using generated types
    fn extract_grpc_web_events(buffer: &mut Vec<u8>) -> Vec<Result<ChatEvent>> {
        let mut events = Vec::new();
        
        while buffer.len() >= 5 {
            let flags = buffer[0];
            let len = u32::from_be_bytes([buffer[1], buffer[2], buffer[3], buffer[4]]) as usize;
            
            if buffer.len() < 5 + len {
                break; // Need more data
            }
            
            let payload = buffer[5..5+len].to_vec();
            buffer.drain(..5+len);
            
            // Trailer frame (end of stream)
            if flags & 0x80 != 0 {
                events.push(Ok(ChatEvent::Done { usage: Usage::default() }));
                continue;
            }
            
            // Try to decode as StreamUnifiedChatResponseWithTools
            match generated::StreamUnifiedChatResponseWithTools::decode(payload.as_slice()) {
                Ok(response) => {
                    // Handle tool calls
                    if let Some(tool_call) = response.client_side_tool_v2_call {
                        let args: serde_json::Value = serde_json::from_str(&tool_call.arguments_json)
                            .unwrap_or(serde_json::Value::Null);
                        events.push(Ok(ChatEvent::ToolCall {
                            name: tool_call.tool_name,
                            args,
                        }));
                    }
                    
                    // Handle text response
                    if let Some(chat_response) = response.stream_unified_chat_response {
                        if !chat_response.text.is_empty() {
                            events.push(Ok(ChatEvent::Text(chat_response.text)));
                        }
                    }
                    
                    // Handle stream end
                    if response.conversation_summary.is_some() {
                        events.push(Ok(ChatEvent::Done { usage: Usage::default() }));
                    }
                }
                Err(e) => {
                    debug!("Failed to decode proto response: {:?}", e);
                    // Try parsing as error message
                    if let Ok(text) = String::from_utf8(payload.clone()) {
                        if !text.is_empty() {
                            events.push(Ok(ChatEvent::Error(text)));
                        }
                    }
                }
            }
        }
        
        events
    }

    /// Parse SSE stream into ChatEvents
    fn parse_sse_stream<S>(stream: S) -> impl Stream<Item = Result<ChatEvent>>
    where
        S: Stream<Item = std::result::Result<bytes::Bytes, reqwest::Error>> + Send + 'static,
    {
        let mut buffer = String::new();
        
        stream.filter_map(move |chunk_result| {
            let events = match chunk_result {
                Ok(chunk) => {
                    buffer.push_str(&String::from_utf8_lossy(&chunk));
                    Self::extract_events(&mut buffer)
                }
                Err(e) => {
                    vec![Err(AgentError::Http(e))]
                }
            };
            
            async move {
                if events.is_empty() {
                    None
                } else {
                    Some(futures::stream::iter(events))
                }
            }
        })
        .flatten()
    }

    /// Extract complete events from buffer
    fn extract_events(buffer: &mut String) -> Vec<Result<ChatEvent>> {
        let mut events = Vec::new();
        
        while let Some(event_end) = buffer.find("\n\n") {
            let event_text = buffer[..event_end].to_string();
            *buffer = buffer[event_end + 2..].to_string();

            if let Some(event) = Self::parse_sse_event(&event_text) {
                events.push(Ok(event));
            }
        }
        
        events
    }

    /// Parse a single SSE event
    fn parse_sse_event(text: &str) -> Option<ChatEvent> {
        let mut event_type = None;
        let mut data = None;

        for line in text.lines() {
            if let Some(value) = line.strip_prefix("event: ") {
                event_type = Some(value.trim().to_string());
            } else if let Some(value) = line.strip_prefix("data: ") {
                data = Some(value.to_string());
            }
        }

        let data = data?;
        
        // Parse based on event type or data content
        if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&data) {
            match parsed.get("type").and_then(|t| t.as_str()) {
                Some("text") => {
                    let content = parsed.get("content")
                        .and_then(|c| c.as_str())
                        .unwrap_or("")
                        .to_string();
                    Some(ChatEvent::Text(content))
                }
                Some("tool_call") => {
                    let name = parsed.get("name")
                        .and_then(|n| n.as_str())
                        .unwrap_or("unknown")
                        .to_string();
                    let args = parsed.get("args")
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    Some(ChatEvent::ToolCall { name, args })
                }
                Some("done") => {
                    let usage = parsed.get("usage")
                        .and_then(|u| serde_json::from_value(u.clone()).ok())
                        .unwrap_or_default();
                    Some(ChatEvent::Done { usage })
                }
                Some("thinking") => Some(ChatEvent::Thinking),
                Some("error") => {
                    let message = parsed.get("message")
                        .and_then(|m| m.as_str())
                        .unwrap_or("Unknown error")
                        .to_string();
                    Some(ChatEvent::Error(message))
                }
                _ => {
                    // Try to extract text from various formats
                    if let Some(content) = parsed.get("content").and_then(|c| c.as_str()) {
                        Some(ChatEvent::Text(content.to_string()))
                    } else if let Some(text) = parsed.get("text").and_then(|t| t.as_str()) {
                        Some(ChatEvent::Text(text.to_string()))
                    } else {
                        debug!("Unknown event format: {:?}", parsed);
                        None
                    }
                }
            }
        } else {
            // Plain text data
            if !data.is_empty() && data != "[DONE]" {
                Some(ChatEvent::Text(data))
            } else {
                None
            }
        }
    }
}

