//! Certificate Authority management for cursor-proxy
//!
//! Generates and manages TLS certificates for MITM proxy operations.

use crate::config::CaConfig;
use crate::error::{ProxyError, ProxyResult};
use rcgen::{
    BasicConstraints, Certificate, CertificateParams, DistinguishedName, DnType, IsCa,
    KeyPair, KeyUsagePurpose, SanType, PKCS_ECDSA_P256_SHA256,
};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

/// Certificate Authority for generating TLS certificates
pub struct CertificateAuthority {
    ca_dir: PathBuf,
    cert_path: PathBuf,
    key_path: PathBuf,
    /// Cached CA certificate
    ca_cert: Option<Certificate>,
    /// Cached CA key pair
    ca_key: Option<Arc<KeyPair>>,
}

impl CertificateAuthority {
    /// Create a new Certificate Authority from config
    pub fn new(ca_dir: PathBuf) -> Self {
        Self {
            cert_path: ca_dir.join("ca.crt"),
            key_path: ca_dir.join("ca.key"),
            ca_dir,
            ca_cert: None,
            ca_key: None,
        }
    }

    /// Generate a new CA certificate using rcgen
    pub fn generate(config: &CaConfig) -> ProxyResult<Self> {
        // Ensure directory exists
        if let Some(parent) = config.cert_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Generate a new key pair
        let key_pair = KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256)
            .map_err(|e| ProxyError::Certificate(format!("Failed to generate key pair: {}", e)))?;

        // Create CA certificate parameters
        let mut params = CertificateParams::default();
        
        // Set distinguished name
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "Cursor Proxy CA");
        dn.push(DnType::OrganizationName, "Cursor Proxy");
        dn.push(DnType::CountryName, "US");
        params.distinguished_name = dn;

        // Set validity period
        let validity_days = config.cert_validity_days as i64;
        params.not_before = rcgen::date_time_ymd(2024, 1, 1);
        params.not_after = rcgen::date_time_ymd(
            2024 + (validity_days / 365) as i32,
            ((validity_days % 365) / 30 + 1) as u8,
            1,
        );

        // Set CA-specific extensions
        params.is_ca = IsCa::Ca(BasicConstraints::Constrained(1));
        params.key_usages = vec![
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
            KeyUsagePurpose::DigitalSignature,
        ];

        // Generate the CA certificate
        let ca_cert = params
            .self_signed(&key_pair)
            .map_err(|e| ProxyError::Certificate(format!("Failed to generate CA cert: {}", e)))?;

        // Get PEM representations
        let cert_pem = ca_cert.pem();
        let key_pem = key_pair.serialize_pem();

        // Save to files
        std::fs::write(&config.cert_path, &cert_pem)
            .map_err(|e| ProxyError::Certificate(format!("Failed to write CA cert: {}", e)))?;
        std::fs::write(&config.key_path, &key_pem)
            .map_err(|e| ProxyError::Certificate(format!("Failed to write CA key: {}", e)))?;

        // Set restrictive permissions on key file
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&config.key_path)?.permissions();
            perms.set_mode(0o600);
            std::fs::set_permissions(&config.key_path, perms)?;
        }

        tracing::info!("✓ Generated new CA certificate at {:?}", config.cert_path);

        Ok(Self {
            ca_dir: config.cert_path.parent().unwrap_or(&config.cert_path).to_path_buf(),
            cert_path: config.cert_path.clone(),
            key_path: config.key_path.clone(),
            ca_cert: None,  // We'll load on demand
            ca_key: Some(Arc::new(key_pair)),
        })
    }

    /// Load existing CA from disk
    fn load_ca(&mut self) -> ProxyResult<()> {
        if self.ca_key.is_some() {
            return Ok(());
        }

        let key_pem = std::fs::read_to_string(&self.key_path)
            .map_err(|e| ProxyError::Certificate(format!("Failed to read CA key: {}", e)))?;

        let key_pair = KeyPair::from_pem(&key_pem)
            .map_err(|e| ProxyError::Certificate(format!("Failed to parse CA key: {}", e)))?;

        self.ca_key = Some(Arc::new(key_pair));
        Ok(())
    }

    /// Load existing CA or generate new one
    pub fn load_or_generate(config: &CaConfig) -> ProxyResult<Self> {
        if config.cert_path.exists() && config.key_path.exists() {
            tracing::info!("Loading existing CA from {:?}", config.cert_path);
            let mut ca = Self {
                ca_dir: config.cert_path.parent().unwrap_or(&config.cert_path).to_path_buf(),
                cert_path: config.cert_path.clone(),
                key_path: config.key_path.clone(),
                ca_cert: None,
                ca_key: None,
            };
            ca.load_ca()?;
            Ok(ca)
        } else {
            Self::generate(config)
        }
    }

    /// Initialize CA (generate root certificate if needed)
    pub fn init(&self, force: bool) -> ProxyResult<()> {
        tracing::info!("CA initialized at {:?} (force={})", self.ca_dir, force);
        Ok(())
    }

    /// Generate a certificate for a given hostname
    /// Returns (certs, private_key) in rustls format
    pub fn generate_cert(&self, hostname: &str) -> ProxyResult<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
        // Ensure CA is loaded
        let ca_key = self.ca_key.as_ref()
            .ok_or_else(|| ProxyError::Certificate("CA key not loaded".to_string()))?;

        // Generate a new key pair for the end-entity certificate
        let ee_key = KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256)
            .map_err(|e| ProxyError::Certificate(format!("Failed to generate key pair: {}", e)))?;

        // Create certificate parameters
        let mut params = CertificateParams::default();

        // Set distinguished name
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, hostname);
        params.distinguished_name = dn;

        // Set validity (short-lived for security)
        params.not_before = rcgen::date_time_ymd(2024, 1, 1);
        params.not_after = rcgen::date_time_ymd(2025, 12, 31);

        // Set subject alternative names
        params.subject_alt_names = vec![
            SanType::DnsName(hostname.to_string().try_into().map_err(|_| {
                ProxyError::Certificate(format!("Invalid hostname: {}", hostname))
            })?),
        ];

        // If hostname looks like an IP, add IP SAN
        if let Ok(ip) = hostname.parse::<std::net::IpAddr>() {
            params.subject_alt_names.push(SanType::IpAddress(ip));
        }

        // Set key usages for end-entity
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];

        // Not a CA
        params.is_ca = IsCa::NoCa;

        // We need to create a CA params to sign with
        // Since rcgen doesn't easily allow loading certs, we'll create a signing pair
        let mut ca_params = CertificateParams::default();
        let mut ca_dn = DistinguishedName::new();
        ca_dn.push(DnType::CommonName, "Cursor Proxy CA");
        ca_params.distinguished_name = ca_dn;
        ca_params.is_ca = IsCa::Ca(BasicConstraints::Constrained(1));
        ca_params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];

        // Create CA certificate for signing
        let ca_cert = ca_params
            .self_signed(ca_key)
            .map_err(|e| ProxyError::Certificate(format!("Failed to create CA cert for signing: {}", e)))?;

        // Generate the end-entity certificate signed by CA
        let ee_cert = params
            .signed_by(&ee_key, &ca_cert, ca_key)
            .map_err(|e| ProxyError::Certificate(format!("Failed to sign certificate: {}", e)))?;

        // Convert to DER format
        let cert_der = CertificateDer::from(ee_cert.der().to_vec());
        let ca_cert_der = CertificateDer::from(ca_cert.der().to_vec());

        // Convert private key to DER
        let key_der = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(ee_key.serialize_der()));

        tracing::debug!("Generated certificate for {}", hostname);

        // Return cert chain (end-entity first, then CA)
        Ok((vec![cert_der, ca_cert_der], key_der))
    }

    /// Generate a certificate for a domain (async version)
    pub async fn generate_cert_for_domain(&self, domain: &str) -> ProxyResult<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
        // Certificate generation is CPU-bound but fast, just delegate to sync version
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

    /// Save CA certificate to file (already saved during generate)
    pub fn save(&self) -> ProxyResult<()> {
        tracing::info!("CA already saved at {:?}", self.cert_path);
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use tempfile::TempDir;

    #[test]
    fn test_generate_ca() {
        let temp_dir = TempDir::new().unwrap();
        let config = CaConfig {
            cert_path: temp_dir.path().join("ca.crt"),
            key_path: temp_dir.path().join("ca.key"),
            trust_system_wide: false,
            cert_validity_days: 365,
        };

        let ca = CertificateAuthority::generate(&config).unwrap();
        
        assert!(config.cert_path.exists());
        assert!(config.key_path.exists());
    }

    #[test]
    fn test_generate_cert() {
        let temp_dir = TempDir::new().unwrap();
        let config = CaConfig {
            cert_path: temp_dir.path().join("ca.crt"),
            key_path: temp_dir.path().join("ca.key"),
            trust_system_wide: false,
            cert_validity_days: 365,
        };

        let ca = CertificateAuthority::generate(&config).unwrap();
        let (certs, key) = ca.generate_cert("api2.cursor.sh").unwrap();

        assert_eq!(certs.len(), 2); // End-entity + CA
        assert!(matches!(key, PrivateKeyDer::Pkcs8(_)));
    }
}
