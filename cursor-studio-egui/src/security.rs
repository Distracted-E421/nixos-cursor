//! Security module for Cursor Studio
//! Provides npm package security scanning, CVE checking, and blocklist enforcement

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Known malicious package blocklist
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Blocklist {
    pub version: String,
    #[serde(rename = "lastUpdated")]
    pub last_updated: String,
    pub description: String,
    pub sources: Vec<String>,
    pub packages: HashMap<String, PackageCategory>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PackageCategory {
    pub description: String,
    pub packages: Vec<BlockedPackage>,
    #[serde(default)]
    pub indicators_of_compromise: Option<IndicatorsOfCompromise>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct BlockedPackage {
    pub name: String,
    pub versions: Vec<String>,
    pub reason: String,
    #[serde(default)]
    pub cve: Option<String>,
    #[serde(default)]
    pub discovered: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct IndicatorsOfCompromise {
    #[serde(default)]
    pub postinstall_patterns: Vec<String>,
    #[serde(default)]
    pub file_patterns: Vec<String>,
    #[serde(default)]
    pub network_indicators: Vec<String>,
}

/// Result of a package security scan
#[derive(Debug, Clone, Default)]
pub struct PackageScanResult {
    pub package_name: String,
    pub version: Option<String>,
    pub is_blocked: bool,
    pub block_reason: Option<String>,
    pub cve: Option<String>,
    pub category: Option<String>,
    pub severity: ScanSeverity,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ScanSeverity {
    #[default]
    Safe,
    Warning,
    Critical,
    Blocked,
}

/// CVE information from public APIs
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CveInfo {
    pub id: String,
    pub description: String,
    pub severity: String,
    pub published: String,
    pub affected_packages: Vec<String>,
}

/// NPM package info from registry
#[derive(Debug, Clone, Deserialize)]
pub struct NpmPackageInfo {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub dependencies: HashMap<String, String>,
    #[serde(rename = "devDependencies", default)]
    pub dev_dependencies: HashMap<String, String>,
}

/// Security scanner for npm packages
pub struct SecurityScanner {
    blocklist: Option<Blocklist>,
    blocked_packages: Vec<String>,
}

impl SecurityScanner {
    pub fn new() -> Self {
        let mut scanner = Self {
            blocklist: None,
            blocked_packages: Vec::new(),
        };
        scanner.load_embedded_blocklist();
        scanner
    }
    
    /// Load the embedded blocklist from the binary or file
    fn load_embedded_blocklist(&mut self) {
        // Try to load from embedded data first
        let blocklist_json = include_str!("../security/known-malicious.json");
        
        if let Ok(blocklist) = serde_json::from_str::<Blocklist>(blocklist_json) {
            // Extract all blocked package names
            self.blocked_packages = blocklist.packages
                .values()
                .flat_map(|cat| cat.packages.iter().map(|p| p.name.clone()))
                .collect();
            self.blocklist = Some(blocklist);
        }
    }
    
    /// Check if a package is blocked
    pub fn is_blocked(&self, package_name: &str, version: Option<&str>) -> Option<PackageScanResult> {
        let blocklist = self.blocklist.as_ref()?;
        
        for (category_name, category) in &blocklist.packages {
            for pkg in &category.packages {
                if pkg.name == package_name {
                    // Check version
                    let version_match = match version {
                        Some(v) => pkg.versions.contains(&"*".to_string()) || pkg.versions.contains(&v.to_string()),
                        None => true, // If no version specified, assume blocked
                    };
                    
                    if version_match {
                        return Some(PackageScanResult {
                            package_name: package_name.to_string(),
                            version: version.map(|v| v.to_string()),
                            is_blocked: true,
                            block_reason: Some(pkg.reason.clone()),
                            cve: pkg.cve.clone(),
                            category: Some(category_name.clone()),
                            severity: ScanSeverity::Blocked,
                        });
                    }
                }
            }
        }
        
        None
    }
    
    /// Scan a package.json file for blocked packages
    pub fn scan_package_json(&self, path: &PathBuf) -> Result<Vec<PackageScanResult>> {
        let content = std::fs::read_to_string(path)?;
        let package: serde_json::Value = serde_json::from_str(&content)?;
        
        let mut results = Vec::new();
        
        // Check dependencies
        if let Some(deps) = package.get("dependencies").and_then(|d| d.as_object()) {
            for (name, version) in deps {
                let version_str = version.as_str().unwrap_or("*");
                if let Some(result) = self.is_blocked(name, Some(version_str)) {
                    results.push(result);
                }
            }
        }
        
        // Check devDependencies
        if let Some(deps) = package.get("devDependencies").and_then(|d| d.as_object()) {
            for (name, version) in deps {
                let version_str = version.as_str().unwrap_or("*");
                if let Some(result) = self.is_blocked(name, Some(version_str)) {
                    results.push(result);
                }
            }
        }
        
        Ok(results)
    }
    
    /// Scan a directory for package.json files
    pub fn scan_directory(&self, path: &PathBuf) -> Result<Vec<(PathBuf, Vec<PackageScanResult>)>> {
        let mut all_results = Vec::new();
        
        // Find all package.json files
        for entry in walkdir::WalkDir::new(path)
            .follow_links(true)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            if entry.file_name() == "package.json" {
                if let Ok(results) = self.scan_package_json(&entry.path().to_path_buf()) {
                    if !results.is_empty() {
                        all_results.push((entry.path().to_path_buf(), results));
                    }
                }
            }
        }
        
        Ok(all_results)
    }
    
    /// Get blocklist statistics
    pub fn get_blocklist_stats(&self) -> BlocklistStats {
        let blocklist = match &self.blocklist {
            Some(b) => b,
            None => return BlocklistStats::default(),
        };
        
        let mut stats = BlocklistStats {
            version: blocklist.version.clone(),
            last_updated: blocklist.last_updated.clone(),
            total_packages: 0,
            categories: HashMap::new(),
            packages_with_cve: 0,
        };
        
        for (name, category) in &blocklist.packages {
            let count = category.packages.len();
            stats.total_packages += count;
            stats.categories.insert(name.clone(), count);
            
            for pkg in &category.packages {
                if pkg.cve.is_some() {
                    stats.packages_with_cve += 1;
                }
            }
        }
        
        stats
    }
    
    /// Get all blocked packages (for display)
    pub fn get_all_blocked(&self) -> Vec<&BlockedPackage> {
        self.blocklist
            .as_ref()
            .map(|b| {
                b.packages
                    .values()
                    .flat_map(|cat| cat.packages.iter())
                    .collect()
            })
            .unwrap_or_default()
    }
    
    /// Get blocklist sources
    pub fn get_sources(&self) -> Vec<String> {
        self.blocklist
            .as_ref()
            .map(|b| b.sources.clone())
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone, Default)]
pub struct BlocklistStats {
    pub version: String,
    pub last_updated: String,
    pub total_packages: usize,
    pub categories: HashMap<String, usize>,
    pub packages_with_cve: usize,
}

/// Fetch CVE information from NVD (National Vulnerability Database)
pub async fn fetch_cve_info(cve_id: &str) -> Result<Option<CveInfo>> {
    // NVD API endpoint
    let url = format!(
        "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={}",
        cve_id
    );
    
    // Note: This is a simplified implementation
    // In production, you'd want proper rate limiting and caching
    let response = ureq::get(&url)
        .timeout(std::time::Duration::from_secs(10))
        .call();
    
    match response {
        Ok(resp) => {
            let body: serde_json::Value = resp.into_json()?;
            
            if let Some(vuln) = body.get("vulnerabilities")
                .and_then(|v| v.as_array())
                .and_then(|arr| arr.first())
            {
                let cve = vuln.get("cve").unwrap_or(&serde_json::Value::Null);
                
                let description = cve.get("descriptions")
                    .and_then(|d| d.as_array())
                    .and_then(|arr| arr.iter().find(|d| d.get("lang").and_then(|l| l.as_str()) == Some("en")))
                    .and_then(|d| d.get("value"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("No description available")
                    .to_string();
                
                let severity = cve.get("metrics")
                    .and_then(|m| m.get("cvssMetricV31"))
                    .and_then(|v| v.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|m| m.get("cvssData"))
                    .and_then(|d| d.get("baseSeverity"))
                    .and_then(|s| s.as_str())
                    .unwrap_or("UNKNOWN")
                    .to_string();
                
                let published = cve.get("published")
                    .and_then(|p| p.as_str())
                    .unwrap_or("")
                    .to_string();
                
                return Ok(Some(CveInfo {
                    id: cve_id.to_string(),
                    description,
                    severity,
                    published,
                    affected_packages: Vec::new(),
                }));
            }
            
            Ok(None)
        }
        Err(_) => Ok(None),
    }
}

/// Check Socket.dev for package security info (free tier)
pub fn check_socket_dev(package_name: &str) -> Option<String> {
    // Socket.dev URL for package info
    let url = format!("https://socket.dev/npm/package/{}", package_name);
    Some(url) // Return URL for user to check manually
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_scanner_loads_blocklist() {
        let scanner = SecurityScanner::new();
        assert!(scanner.blocklist.is_some());
    }
    
    #[test]
    fn test_blocked_package() {
        let scanner = SecurityScanner::new();
        let result = scanner.is_blocked("event-stream", Some("3.3.6"));
        assert!(result.is_some());
        assert!(result.unwrap().is_blocked);
    }
    
    #[test]
    fn test_safe_package() {
        let scanner = SecurityScanner::new();
        let result = scanner.is_blocked("lodash", Some("4.17.21"));
        assert!(result.is_none());
    }
}
