//! P2P Sync Module - Device-to-device synchronization using libp2p.
//!
//! Provides:
//! - mDNS local network discovery
//! - Noise encryption for secure connections
//! - Request/response protocol for syncing conversations
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────┐      ┌─────────────────┐
//! │   Device A      │      │   Device B      │
//! │ ┌─────────────┐ │      │ ┌─────────────┐ │
//! │ │ P2P Service │ │◄────►│ │ P2P Service │ │
//! │ │  (libp2p)   │ │ mDNS │ │  (libp2p)   │ │
//! │ └──────┬──────┘ │      │ └──────┬──────┘ │
//! │        │        │      │        │        │
//! │ ┌──────▼──────┐ │      │ ┌──────▼──────┐ │
//! │ │ SurrealDB   │ │      │ │ SurrealDB   │ │
//! │ └─────────────┘ │      │ └─────────────┘ │
//! └─────────────────┘      └─────────────────┘
//! ```

use std::collections::HashSet;
use std::time::Duration;

use futures::StreamExt;
use libp2p::{
    identify, mdns, noise,
    request_response::{self, Codec, ProtocolSupport},
    swarm::{NetworkBehaviour, SwarmEvent},
    tcp, yamux, Multiaddr, PeerId, Swarm,
};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use super::crdt::VectorClock;
use super::surreal::SyncedConversation;

/// Protocol name for chat sync
const PROTOCOL_NAME: &str = "/cursor-sync/1.0.0";

/// P2P configuration
#[derive(Debug, Clone)]
pub struct P2PConfig {
    /// Port to listen on (0 = random)
    pub port: u16,
    /// Enable mDNS discovery
    pub mdns_enabled: bool,
    /// Device name for identification
    pub device_name: String,
}

impl Default for P2PConfig {
    fn default() -> Self {
        Self {
            port: 0, // Random port
            mdns_enabled: true,
            device_name: hostname::get()
                .map(|h| h.to_string_lossy().to_string())
                .unwrap_or_else(|_| "unknown".to_string()),
        }
    }
}

/// Sync request message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncRequest {
    /// Request sync status
    Status,
    /// Request conversations modified since vector clock
    Pull {
        since: Option<VectorClock>,
        limit: usize,
    },
    /// Push conversations to peer
    Push {
        conversations: Vec<SyncedConversation>,
    },
}

/// Sync response message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncResponse {
    /// Status response
    Status {
        device_id: String,
        device_name: String,
        conversation_count: usize,
        vector_clock: VectorClock,
    },
    /// Pull response with conversations
    Pull {
        conversations: Vec<SyncedConversation>,
        vector_clock: VectorClock,
    },
    /// Push acknowledgment
    PushAck {
        accepted: usize,
        rejected: usize,
    },
    /// Error response
    Error {
        message: String,
    },
}

/// JSON codec for sync messages
#[derive(Debug, Clone, Default)]
pub struct SyncCodec;

impl Codec for SyncCodec {
    type Protocol = &'static str;
    type Request = SyncRequest;
    type Response = SyncResponse;

    fn read_request<'life0, 'life1, 'life2, 'async_trait, T>(
        &'life0 mut self,
        _protocol: &'life1 Self::Protocol,
        io: &'life2 mut T,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = std::io::Result<Self::Request>>
                + Send
                + 'async_trait,
        >,
    >
    where
        T: futures::AsyncRead + Unpin + Send + 'async_trait,
        'life0: 'async_trait,
        'life1: 'async_trait,
        'life2: 'async_trait,
        Self: 'async_trait,
    {
        Box::pin(async move {
            use futures::AsyncReadExt;
            
            // Read length prefix (4 bytes, big endian)
            let mut len_buf = [0u8; 4];
            io.read_exact(&mut len_buf).await?;
            let len = u32::from_be_bytes(len_buf) as usize;
            
            // Sanity check
            if len > 10 * 1024 * 1024 {
                // 10MB max
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "Message too large",
                ));
            }
            
            // Read message
            let mut buf = vec![0u8; len];
            io.read_exact(&mut buf).await?;
            
            serde_json::from_slice(&buf)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        })
    }

    fn read_response<'life0, 'life1, 'life2, 'async_trait, T>(
        &'life0 mut self,
        _protocol: &'life1 Self::Protocol,
        io: &'life2 mut T,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = std::io::Result<Self::Response>>
                + Send
                + 'async_trait,
        >,
    >
    where
        T: futures::AsyncRead + Unpin + Send + 'async_trait,
        'life0: 'async_trait,
        'life1: 'async_trait,
        'life2: 'async_trait,
        Self: 'async_trait,
    {
        Box::pin(async move {
            use futures::AsyncReadExt;
            
            let mut len_buf = [0u8; 4];
            io.read_exact(&mut len_buf).await?;
            let len = u32::from_be_bytes(len_buf) as usize;
            
            if len > 100 * 1024 * 1024 {
                // 100MB max for responses
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "Response too large",
                ));
            }
            
            let mut buf = vec![0u8; len];
            io.read_exact(&mut buf).await?;
            
            serde_json::from_slice(&buf)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        })
    }

    fn write_request<'life0, 'life1, 'life2, 'async_trait, T>(
        &'life0 mut self,
        _protocol: &'life1 Self::Protocol,
        io: &'life2 mut T,
        req: Self::Request,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = std::io::Result<()>> + Send + 'async_trait>,
    >
    where
        T: futures::AsyncWrite + Unpin + Send + 'async_trait,
        'life0: 'async_trait,
        'life1: 'async_trait,
        'life2: 'async_trait,
        Self: 'async_trait,
    {
        Box::pin(async move {
            use futures::AsyncWriteExt;
            
            let data = serde_json::to_vec(&req)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            
            let len = (data.len() as u32).to_be_bytes();
            io.write_all(&len).await?;
            io.write_all(&data).await?;
            io.flush().await?;
            
            Ok(())
        })
    }

    fn write_response<'life0, 'life1, 'life2, 'async_trait, T>(
        &'life0 mut self,
        _protocol: &'life1 Self::Protocol,
        io: &'life2 mut T,
        res: Self::Response,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = std::io::Result<()>> + Send + 'async_trait>,
    >
    where
        T: futures::AsyncWrite + Unpin + Send + 'async_trait,
        'life0: 'async_trait,
        'life1: 'async_trait,
        'life2: 'async_trait,
        Self: 'async_trait,
    {
        Box::pin(async move {
            use futures::AsyncWriteExt;
            
            let data = serde_json::to_vec(&res)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            
            let len = (data.len() as u32).to_be_bytes();
            io.write_all(&len).await?;
            io.write_all(&data).await?;
            io.flush().await?;
            
            Ok(())
        })
    }
}

/// Combined network behaviour
#[derive(NetworkBehaviour)]
pub struct SyncBehaviour {
    /// Request/response for sync messages
    pub sync: request_response::Behaviour<SyncCodec>,
    /// mDNS for local peer discovery
    pub mdns: mdns::tokio::Behaviour,
    /// Identify protocol for peer info
    pub identify: identify::Behaviour,
}

/// Discovered peer information
#[derive(Debug, Clone)]
pub struct DiscoveredPeer {
    pub peer_id: PeerId,
    pub addrs: Vec<Multiaddr>,
    pub device_name: Option<String>,
}

/// Events emitted by the P2P service
#[derive(Debug)]
pub enum P2PEvent {
    /// New peer discovered
    PeerDiscovered(DiscoveredPeer),
    /// Peer went offline
    PeerExpired(PeerId),
    /// Incoming sync request
    SyncRequest {
        peer_id: PeerId,
        request: SyncRequest,
        channel: request_response::ResponseChannel<SyncResponse>,
    },
    /// Sync response received
    SyncResponse {
        peer_id: PeerId,
        response: SyncResponse,
    },
    /// Listening on address
    Listening(Multiaddr),
    /// Error occurred
    Error(String),
}

/// P2P sync service
pub struct P2PService {
    /// Our peer ID
    peer_id: PeerId,
    /// Configuration
    config: P2PConfig,
    /// Known peers
    known_peers: HashSet<PeerId>,
    /// Event sender for the application
    event_tx: mpsc::Sender<P2PEvent>,
}

impl P2PService {
    /// Create a new P2P service
    pub fn new(config: P2PConfig) -> anyhow::Result<(Self, mpsc::Receiver<P2PEvent>, Swarm<SyncBehaviour>)> {
        // Generate keypair for this device
        let keypair = libp2p::identity::Keypair::generate_ed25519();
        let peer_id = PeerId::from(keypair.public());
        
        log::info!("P2P Peer ID: {}", peer_id);
        
        // Build the swarm
        let swarm = libp2p::SwarmBuilder::with_existing_identity(keypair)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|key| {
                // Request/response for sync
                let sync = request_response::Behaviour::new(
                    [(PROTOCOL_NAME, ProtocolSupport::Full)],
                    request_response::Config::default(),
                );
                
                // mDNS for local discovery
                let mdns = mdns::tokio::Behaviour::new(
                    mdns::Config::default(),
                    key.public().to_peer_id(),
                )?;
                
                // Identify for peer info exchange
                let identify = identify::Behaviour::new(identify::Config::new(
                    "/cursor-studio/1.0.0".to_string(),
                    key.public(),
                ));
                
                Ok(SyncBehaviour { sync, mdns, identify })
            })?
            .with_swarm_config(|cfg| {
                cfg.with_idle_connection_timeout(Duration::from_secs(60))
            })
            .build();
        
        let (event_tx, event_rx) = mpsc::channel(100);
        
        let service = Self {
            peer_id,
            config,
            known_peers: HashSet::new(),
            event_tx,
        };
        
        Ok((service, event_rx, swarm))
    }
    
    /// Get our peer ID
    pub fn peer_id(&self) -> &PeerId {
        &self.peer_id
    }
    
    /// Get known peers
    pub fn known_peers(&self) -> &HashSet<PeerId> {
        &self.known_peers
    }
    
    /// Run the P2P service event loop
    pub async fn run(mut self, mut swarm: Swarm<SyncBehaviour>) -> anyhow::Result<()> {
        // Listen on all interfaces
        let listen_addr: Multiaddr = format!("/ip4/0.0.0.0/tcp/{}", self.config.port).parse()?;
        swarm.listen_on(listen_addr)?;
        
        log::info!("P2P service starting...");
        
        loop {
            match swarm.select_next_some().await {
                SwarmEvent::NewListenAddr { address, .. } => {
                    log::info!("Listening on {}", address);
                    let _ = self.event_tx.send(P2PEvent::Listening(address)).await;
                }
                
                SwarmEvent::Behaviour(SyncBehaviourEvent::Mdns(mdns::Event::Discovered(peers))) => {
                    for (peer_id, addr) in peers {
                        if peer_id != self.peer_id && !self.known_peers.contains(&peer_id) {
                            log::info!("Discovered peer: {} at {}", peer_id, addr);
                            self.known_peers.insert(peer_id);
                            swarm.dial(addr.clone()).ok();
                            
                            let _ = self.event_tx.send(P2PEvent::PeerDiscovered(DiscoveredPeer {
                                peer_id,
                                addrs: vec![addr],
                                device_name: None,
                            })).await;
                        }
                    }
                }
                
                SwarmEvent::Behaviour(SyncBehaviourEvent::Mdns(mdns::Event::Expired(peers))) => {
                    for (peer_id, _) in peers {
                        log::info!("Peer expired: {}", peer_id);
                        self.known_peers.remove(&peer_id);
                        let _ = self.event_tx.send(P2PEvent::PeerExpired(peer_id)).await;
                    }
                }
                
                SwarmEvent::Behaviour(SyncBehaviourEvent::Sync(
                    request_response::Event::Message { peer, message }
                )) => {
                    match message {
                        request_response::Message::Request { request, channel, .. } => {
                            log::debug!("Received sync request from {}", peer);
                            let _ = self.event_tx.send(P2PEvent::SyncRequest {
                                peer_id: peer,
                                request,
                                channel,
                            }).await;
                        }
                        request_response::Message::Response { response, .. } => {
                            log::debug!("Received sync response from {}", peer);
                            let _ = self.event_tx.send(P2PEvent::SyncResponse {
                                peer_id: peer,
                                response,
                            }).await;
                        }
                    }
                }
                
                SwarmEvent::Behaviour(SyncBehaviourEvent::Identify(identify::Event::Received { peer_id, info, .. })) => {
                    log::debug!("Identified peer {}: {:?}", peer_id, info.protocol_version);
                }
                
                SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                    log::info!("Connected to peer: {}", peer_id);
                }
                
                SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                    log::info!("Disconnected from peer {}: {:?}", peer_id, cause);
                }
                
                SwarmEvent::OutgoingConnectionError { peer_id: Some(peer), error, .. } => {
                    log::warn!("Failed to connect to {}: {}", peer, error);
                }
                
                SwarmEvent::OutgoingConnectionError { peer_id: None, .. } => {}
                
                _ => {}
            }
        }
    }
    
    /// Send a sync request to a peer
    pub fn send_request(swarm: &mut Swarm<SyncBehaviour>, peer_id: &PeerId, request: SyncRequest) {
        swarm.behaviour_mut().sync.send_request(peer_id, request);
    }
    
    /// Send a response on a channel
    pub fn send_response(
        swarm: &mut Swarm<SyncBehaviour>,
        channel: request_response::ResponseChannel<SyncResponse>,
        response: SyncResponse,
    ) {
        if let Err(e) = swarm.behaviour_mut().sync.send_response(channel, response) {
            log::warn!("Failed to send response: {:?}", e);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = P2PConfig::default();
        assert_eq!(config.port, 0);
        assert!(config.mdns_enabled);
    }

    #[test]
    fn test_sync_request_serialization() {
        let request = SyncRequest::Status;
        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("Status"));

        let request = SyncRequest::Pull {
            since: None,
            limit: 100,
        };
        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("Pull"));
    }

    #[test]
    fn test_sync_response_serialization() {
        let response = SyncResponse::Status {
            device_id: "test".to_string(),
            device_name: "My Device".to_string(),
            conversation_count: 42,
            vector_clock: VectorClock::new(),
        };
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("Status"));
        assert!(json.contains("42"));
    }
}
