//! Test file for injection module (not compiled by default)

#[cfg(test)]
mod tests {
    use super::injection::*;
    use bytes::Bytes;
    
    #[test]
    fn test_varint_encoding() {
        let mut buf = Vec::new();
        write_varint(&mut buf, 300);
        assert_eq!(buf, vec![0xac, 0x02]);
        
        let (value, len) = read_varint(&buf).unwrap();
        assert_eq!(value, 300);
        assert_eq!(len, 2);
    }
    
    #[test]
    fn test_conversation_message_encoding() {
        let msg = encode_conversation_message("Hello", 3, "test-id");
        
        // Should contain field 1 (text), field 2 (type), field 13 (bubble_id)
        assert!(msg.contains(&0x0a)); // tag for field 1
        assert!(msg.contains(&0x10)); // tag for field 2
        assert!(msg.contains(&0x6a)); // tag for field 13
    }
    
    #[tokio::test]
    async fn test_injection_engine_config() {
        let config = InjectionConfig {
            enabled: true,
            system_prompt: Some("Test prompt".to_string()),
            ..Default::default()
        };
        
        let engine = InjectionEngine::new(config);
        assert!(engine.is_enabled().await);
    }
}
