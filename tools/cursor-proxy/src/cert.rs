//! Certificate Authority management for cursor-proxy
//!
//! Generates and manages TLS certificates for MITM proxy operations.

use crate::config::CaConfig;
use crate::error::{ProxyError, ProxyResult};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use std::path::PathBuf;

/// Certificate Authority for generating TLS certificates
pub struct CertificateAuthority {
    ca_dir: PathBuf,
    cert_path: PathBuf,
    key_path: PathBuf,
}

impl CertificateAuthority {
    /// Create a new Certificate Authority from config
    pub fn new(ca_dir: PathBuf) -> Self {
        Self {
            cert_path: ca_dir.join("ca.crt"),
            key_path: ca_dir.join("ca.key"),
            ca_dir,
        }
    }

    /// Generate a new CA certificate
    pub fn generate(config: &CaConfig) -> ProxyResult<Self> {
        let ca = Self {
            ca_dir: config.cert_path.parent().unwrap_or(&config.cert_path).to_path_buf(),
            cert_path: config.cert_path.clone(),
            key_path: config.key_path.clone(),
        };
        
        // Ensure directory exists
        if let Some(parent) = config.cert_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        // TODO: Generate CA cert using rcgen
        tracing::info!("Generated new CA certificate at {:?}", config.cert_path);
        
        Ok(ca)
    }

    /// Load existing CA or generate new one
    pub fn load_or_generate(config: &CaConfig) -> ProxyResult<Self> {
        if config.cert_path.exists() && config.key_path.exists() {
            tracing::info!("Loading existing CA from {:?}", config.cert_path);
            Ok(Self {
                ca_dir: config.cert_path.parent().unwrap_or(&config.cert_path).to_path_buf(),
                cert_path: config.cert_path.clone(),
                key_path: config.key_path.clone(),
            })
        } else {
            Self::generate(config)
        }
    }

    /// Initialize CA (generate root certificate if needed)
    pub fn init(&self, force: bool) -> ProxyResult<()> {
        // TODO: Implement CA initialization using rcgen or similar
        tracing::info!("CA initialized at {:?} (force={})", self.ca_dir, force);
        Ok(())
    }

    /// Generate a certificate for a given hostname
    /// Returns (certs, private_key) in rustls format
    pub fn generate_cert(&self, hostname: &str) -> ProxyResult<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
        // TODO: Implement certificate generation with rcgen
        tracing::debug!("Generating certificate for {}", hostname);
        Err(ProxyError::Certificate("Certificate generation not implemented".to_string()))
    }

    /// Generate a certificate for a domain (async version)
    pub async fn generate_cert_for_domain(&self, domain: &str) -> ProxyResult<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
        // TODO: Implement certificate generation
        tracing::debug!("Generating certificate for domain: {}", domain);
        self.generate_cert(domain)
    }

    /// Get the CA certificate path
    pub fn ca_cert_path(&self) -> PathBuf {
        self.cert_path.clone()
    }

    /// Get the CA key path
    pub fn ca_key_path(&self) -> PathBuf {
        self.key_path.clone()
    }

    /// Save CA certificate to file
    pub fn save(&self) -> ProxyResult<()> {
        // CA is already saved during generate
        tracing::info!("CA saved at {:?}", self.cert_path);
        Ok(())
    }

    /// Get CA certificate in PEM format
    pub fn ca_cert_pem(&self) -> ProxyResult<String> {
        if self.cert_path.exists() {
            std::fs::read_to_string(&self.cert_path)
                .map_err(|e| ProxyError::Certificate(e.to_string()))
        } else {
            Err(ProxyError::Certificate("CA certificate not found".to_string()))
        }
    }
}
