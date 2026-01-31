//! Test binary to generate proper protobuf requests

use prost::Message;

// Include generated types
mod generated {
    include!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/generated/aiserver.v1.rs"));
}

use generated::*;

fn main() {
    // Build a minimal request using the generated types
    let conversation_message = ConversationMessage {
        text: "What is 2+2? Reply with just the number 4.".to_string(),
        r#type: conversation_message::MessageType::User as i32,
        bubble_id: "bubble-001".to_string(),
        ..Default::default()
    };

    let model_details = ModelDetails {
        model_name: "claude-3.5-sonnet".to_string(),
        supports_tools: true,
        ..Default::default()
    };

    let chat_request = StreamUnifiedChatRequest {
        conversation: vec![conversation_message],
        model_details: Some(model_details),
        is_chat: true,
        conversation_id: "conv-001".to_string(),
        ..Default::default()
    };

    let request_with_tools = StreamUnifiedChatRequestWithTools {
        stream_unified_chat_request: Some(chat_request),
        client_side_tool_v2_result: None,
    };

    // Encode to protobuf
    let mut buf = Vec::new();
    request_with_tools.encode(&mut buf).expect("Failed to encode");
    
    eprintln!("Encoded payload: {} bytes", buf.len());
    
    // Add Connect Protocol framing
    let mut framed = Vec::with_capacity(5 + buf.len());
    framed.push(0x00); // flags: uncompressed
    framed.extend_from_slice(&(buf.len() as u32).to_be_bytes());
    framed.extend_from_slice(&buf);
    
    eprintln!("Framed message: {} bytes", framed.len());
    eprintln!("Hex: {:02x?}", &framed[..std::cmp::min(100, framed.len())]);
    
    // Write to stdout
    use std::io::Write;
    std::io::stdout().write_all(&framed).unwrap();
}
