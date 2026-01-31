use crate::auth::CursorAuth;
use crate::aiserver::v1::chat_service_client::ChatServiceClient;
use crate::aiserver::v1::{StreamUnifiedChatRequestWithTools, StreamUnifiedChatRequest, ConversationMessage};
use anyhow::Result;
use tonic::{transport::{Channel, ClientTlsConfig}, Request, metadata::MetadataValue};
use tracing::{info, error};

pub struct Client {
    auth: CursorAuth,
    channel: Channel,
}

impl Client {
    pub async fn new(auth: CursorAuth) -> Result<Self> {
        let tls = ClientTlsConfig::new();
        
        let channel = Channel::from_static("https://api2.cursor.sh")
            .tls_config(tls)?
            .connect()
            .await?;

        Ok(Self {
            auth,
            channel,
        })
    }

    pub async fn send_dummy_request(&mut self) -> Result<()> {
        let token = self.auth.access_token.clone();
        
        let mut grpc_client = ChatServiceClient::with_interceptor(self.channel.clone(), move |mut req: Request<()>| {
            let token_val = MetadataValue::try_from(&format!("Bearer {}", token)).unwrap();
            req.metadata_mut().insert("authorization", token_val);
            
            // Add client version
            let version_val = MetadataValue::from_static("99.99.99");
            req.metadata_mut().insert("x-cursor-client-version", version_val);
            
            // Placeholder checksum?
            // let checksum_val = MetadataValue::from_static("placeholder");
            // req.metadata_mut().insert("x-cursor-checksum", checksum_val);

            Ok(req)
        });

        let request_msg = StreamUnifiedChatRequestWithTools {
            stream_unified_chat_request: Some(StreamUnifiedChatRequest {
                conversation: vec![ConversationMessage {
                    text: "Hello, are you there?".to_string(),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        };

        // Create a stream for the request
        let request_stream = tokio_stream::iter(vec![request_msg]);

        info!("Sending request...");
        let response = grpc_client.stream_unified_chat_with_tools(request_stream).await;

        match response {
            Ok(resp) => {
                info!("Response received: {:?}", resp.metadata());
                let mut stream = resp.into_inner();
                
                while let Some(msg) = stream.message().await? {
                    info!("Received message: {:?}", msg);
                    println!("Received message!");
                }
                info!("Stream finished");
            },
            Err(status) => {
                error!("gRPC Error: {:?}", status);
                println!("gRPC Error: {:?}", status);
            }
        }

        Ok(())
    }
}
