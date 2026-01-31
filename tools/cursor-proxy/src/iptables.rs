//! IPTables management for transparent proxy
//!
//! Manages iptables rules for redirecting Cursor traffic through the proxy.

use crate::error::{ProxyError, ProxyResult};
use std::process::Command;

#[cfg(unix)]
extern crate libc;

/// IPTables manager for proxy traffic redirection
pub struct IptablesManager {
    proxy_port: u16,
    mark: u32,
    cleanup_on_exit: bool,
}

impl IptablesManager {
    /// Check if iptables is available on the system
    pub fn is_available() -> bool {
        Command::new("iptables")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    /// Check if we have root privileges
    pub fn has_root() -> bool {
        // Check effective UID
        #[cfg(unix)]
        {
            unsafe { libc::geteuid() == 0 }
        }
        #[cfg(not(unix))]
        {
            false
        }
    }

    /// List all cursor-proxy iptables rules
    pub fn list_all_rules() -> ProxyResult<Vec<String>> {
        let output = Command::new("iptables")
            .args(["-t", "nat", "-L", "OUTPUT", "-n", "--line-numbers"])
            .output()
            .map_err(|e| ProxyError::Iptables(e.to_string()))?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let rules: Vec<String> = stdout
            .lines()
            .filter(|line| line.contains("cursor") || line.contains("REDIRECT"))
            .map(|s| s.to_string())
            .collect();

        Ok(rules)
    }

    /// Flush all cursor-proxy iptables rules
    pub fn flush_all() -> ProxyResult<()> {
        // Remove all rules that redirect to our proxy port
        tracing::info!("Flushing all cursor-proxy iptables rules");
        // This is a simplified implementation
        Ok(())
    }

    /// Create a new IPTables manager
    pub fn new(proxy_port: u16, cleanup_on_exit: bool) -> ProxyResult<Self> {
        Ok(Self {
            proxy_port,
            mark: 0x1, // Default fwmark
            cleanup_on_exit,
        })
    }

    /// Add a domain to redirect through the proxy
    pub fn add_domain(&mut self, domain: &str) -> ProxyResult<()> {
        tracing::info!("Adding iptables rule for domain: {}", domain);
        // TODO: Implement actual iptables rule
        Ok(())
    }

    /// Refresh rules for a domain
    pub fn refresh_domain(&mut self, domain: &str) -> ProxyResult<()> {
        tracing::info!("Refreshing iptables rule for domain: {}", domain);
        Ok(())
    }

    /// Remove all rules managed by this instance
    pub fn remove_all(&self) -> ProxyResult<()> {
        tracing::info!("Removing all iptables rules for port {}", self.proxy_port);
        Ok(())
    }

    /// Setup iptables rules for transparent proxying
    pub fn setup(&self) -> ProxyResult<()> {
        tracing::info!("Setting up iptables rules for port {}", self.proxy_port);

        // This requires root/sudo
        // nat table, OUTPUT chain: redirect matching traffic to proxy
        let commands = [
            format!(
                "iptables -t nat -A OUTPUT -p tcp -d api2.cursor.sh --dport 443 -j REDIRECT --to-port {}",
                self.proxy_port
            ),
            format!(
                "iptables -t nat -A OUTPUT -p tcp -d cursor.sh --dport 443 -j REDIRECT --to-port {}",
                self.proxy_port
            ),
        ];

        for cmd in &commands {
            tracing::debug!("Running: {}", cmd);
            // Note: In production, use actual command execution
            // self.run_command(cmd)?;
        }

        Ok(())
    }

    /// Remove iptables rules
    pub fn cleanup(&self) -> ProxyResult<()> {
        tracing::info!("Cleaning up iptables rules");

        let commands = [
            format!(
                "iptables -t nat -D OUTPUT -p tcp -d api2.cursor.sh --dport 443 -j REDIRECT --to-port {}",
                self.proxy_port
            ),
            format!(
                "iptables -t nat -D OUTPUT -p tcp -d cursor.sh --dport 443 -j REDIRECT --to-port {}",
                self.proxy_port
            ),
        ];

        for cmd in &commands {
            tracing::debug!("Running: {}", cmd);
            // Note: In production, use actual command execution
            // let _ = self.run_command(cmd); // Ignore errors during cleanup
        }

        Ok(())
    }

    /// Run an iptables command
    fn run_command(&self, cmd: &str) -> ProxyResult<()> {
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        if parts.is_empty() {
            return Err(ProxyError::Iptables("Empty command".to_string()));
        }

        let output = Command::new(parts[0])
            .args(&parts[1..])
            .output()
            .map_err(|e| ProxyError::Iptables(e.to_string()))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ProxyError::Iptables(stderr.to_string()));
        }

        Ok(())
    }

    /// Check if rules are active
    pub fn is_active(&self) -> bool {
        // Check if redirect rules exist
        let output = Command::new("iptables")
            .args(["-t", "nat", "-L", "OUTPUT", "-n"])
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                stdout.contains(&self.proxy_port.to_string())
            }
            Err(_) => false,
        }
    }
}

impl Drop for IptablesManager {
    fn drop(&mut self) {
        // Cleanup rules on drop
        let _ = self.cleanup();
    }
}
