//! Terminal dashboard with LED-style status indicators
//!
//! Uses ANSI 16-color palette for terminal theme compatibility.
//! Colors adapt to light/dark terminal themes automatically.

use crate::events::{EventReceiver, ProxyEvent, ServiceCategory, AgentActivityType};
use std::collections::HashMap;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::interval;

// ============================================================================
// ANSI 16-color codes (theme-aware)
// These colors adapt to the user's terminal color scheme
// ============================================================================

mod colors {
    // Standard colors (adapt to terminal theme)
    pub const BLACK: &str = "\x1b[30m";
    pub const RED: &str = "\x1b[31m";
    pub const GREEN: &str = "\x1b[32m";
    pub const YELLOW: &str = "\x1b[33m";
    pub const BLUE: &str = "\x1b[34m";
    pub const MAGENTA: &str = "\x1b[35m";
    pub const CYAN: &str = "\x1b[36m";
    pub const WHITE: &str = "\x1b[37m";
    
    // Bright colors
    pub const BRIGHT_BLACK: &str = "\x1b[90m";   // Gray
    pub const BRIGHT_RED: &str = "\x1b[91m";
    pub const BRIGHT_GREEN: &str = "\x1b[92m";
    pub const BRIGHT_YELLOW: &str = "\x1b[93m";
    pub const BRIGHT_BLUE: &str = "\x1b[94m";
    pub const BRIGHT_MAGENTA: &str = "\x1b[95m";
    pub const BRIGHT_CYAN: &str = "\x1b[96m";
    pub const BRIGHT_WHITE: &str = "\x1b[97m";
    
    pub const RESET: &str = "\x1b[0m";
    pub const BOLD: &str = "\x1b[1m";
    pub const DIM: &str = "\x1b[2m";
    
    // Semantic aliases
    pub const BORDER: &str = CYAN;
    pub const HEADER: &str = BRIGHT_WHITE;
    pub const LABEL: &str = BRIGHT_BLACK;
    pub const VALUE: &str = WHITE;
    pub const SUCCESS: &str = GREEN;
    pub const ERROR: &str = RED;
    pub const WARNING: &str = YELLOW;
    pub const STREAMING: &str = MAGENTA;
    pub const CHAT: &str = MAGENTA;
    pub const AI: &str = CYAN;
    pub const QUEUE: &str = BLUE;
    pub const TELEMETRY: &str = YELLOW;
    pub const SYSTEM: &str = GREEN;
}

/// LED state with decay
#[derive(Debug, Clone)]
struct Led {
    brightness: f32,
    state: LedState,
    last_activity: Instant,
    activity_count: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum LedState {
    Idle,
    Active,
    Success,
    Error,
    Streaming,
}

impl Led {
    fn new() -> Self {
        Self {
            brightness: 0.0,
            state: LedState::Idle,
            last_activity: Instant::now(),
            activity_count: 0,
        }
    }
    
    fn trigger(&mut self, state: LedState) {
        self.brightness = 1.0;
        self.state = state;
        self.last_activity = Instant::now();
        self.activity_count += 1;
    }
    
    fn decay(&mut self, decay_rate: f32) {
        self.brightness = (self.brightness - decay_rate).max(0.0);
        if self.brightness == 0.0 {
            self.state = LedState::Idle;
        }
    }
    
    fn render(&self) -> String {
        let (color, char) = match (self.state, self.brightness > 0.5) {
            (LedState::Idle, _) => (colors::BRIGHT_BLACK, "○"),
            (LedState::Active, true) => (colors::BRIGHT_WHITE, "●"),
            (LedState::Active, false) => (colors::WHITE, "◐"),
            (LedState::Success, true) => (colors::BRIGHT_GREEN, "●"),
            (LedState::Success, false) => (colors::GREEN, "◐"),
            (LedState::Error, true) => (colors::BRIGHT_RED, "●"),
            (LedState::Error, false) => (colors::RED, "◐"),
            (LedState::Streaming, true) => (colors::BRIGHT_MAGENTA, "◉"),
            (LedState::Streaming, false) => (colors::MAGENTA, "◉"),
        };
        format!("{}{}{}", color, char, colors::RESET)
    }
}

/// Activity log entry
#[derive(Debug, Clone)]
struct ActivityEntry {
    timestamp: Instant,
    category: ServiceCategory,
    endpoint: String,
    status: Option<u16>,
    duration_ms: Option<u64>,
    is_streaming: bool,
}

/// In-flight request tracking
#[derive(Debug, Clone)]
struct InFlightRequest {
    path: String,
    category: ServiceCategory,
    endpoint: String,
    started: Instant,
}

/// Maximum age for in-flight requests before they're considered stale (5 minutes)
const MAX_IN_FLIGHT_AGE_SECS: u64 = 300;

/// Maximum number of in-flight requests to track
const MAX_IN_FLIGHT_ENTRIES: usize = 1000;

/// Error types for breakdown
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ErrorType {
    Timeout,
    Upstream,
    Tls,
    Network,
    Protocol,
    Unknown,
}

impl ErrorType {
    fn from_error(error: &str) -> Self {
        let lower = error.to_lowercase();
        if lower.contains("timeout") || lower.contains("timed out") {
            ErrorType::Timeout
        } else if lower.contains("upstream") || lower.contains("502") || lower.contains("503") {
            ErrorType::Upstream
        } else if lower.contains("tls") || lower.contains("ssl") || lower.contains("certificate") {
            ErrorType::Tls
        } else if lower.contains("connection") || lower.contains("network") || lower.contains("refused") {
            ErrorType::Network
        } else if lower.contains("protocol") || lower.contains("http") {
            ErrorType::Protocol
        } else {
            ErrorType::Unknown
        }
    }
    
    fn name(&self) -> &'static str {
        match self {
            ErrorType::Timeout => "Timeout",
            ErrorType::Upstream => "Upstream",
            ErrorType::Tls => "TLS",
            ErrorType::Network => "Network",
            ErrorType::Protocol => "Protocol",
            ErrorType::Unknown => "Other",
        }
    }
    
    fn color(&self) -> &'static str {
        match self {
            ErrorType::Timeout => colors::YELLOW,
            ErrorType::Upstream => colors::RED,
            ErrorType::Tls => colors::MAGENTA,
            ErrorType::Network => colors::BLUE,
            ErrorType::Protocol => colors::CYAN,
            ErrorType::Unknown => colors::WHITE,
        }
    }
}

/// Latency stats
#[derive(Debug, Clone, Default)]
struct LatencyStats {
    samples: Vec<u64>,
    max_samples: usize,
}

impl LatencyStats {
    fn new(max_samples: usize) -> Self {
        Self { samples: Vec::with_capacity(max_samples), max_samples }
    }
    
    fn add(&mut self, latency_ms: u64) {
        if self.samples.len() >= self.max_samples {
            self.samples.remove(0);
        }
        self.samples.push(latency_ms);
    }
    
    fn percentile(&self, p: f64) -> Option<u64> {
        if self.samples.is_empty() { return None; }
        let mut sorted = self.samples.clone();
        sorted.sort();
        let idx = ((p / 100.0) * (sorted.len() - 1) as f64) as usize;
        Some(sorted[idx])
    }
    
    fn avg(&self) -> Option<u64> {
        if self.samples.is_empty() { return None; }
        Some(self.samples.iter().sum::<u64>() / self.samples.len() as u64)
    }
}

/// Rate tracker
#[derive(Debug, Clone)]
struct RateTracker {
    window_start: Instant,
    count: u64,
    rate: f64, // requests per second
}

impl RateTracker {
    fn new() -> Self {
        Self { window_start: Instant::now(), count: 0, rate: 0.0 }
    }
    
    fn tick(&mut self) {
        self.count += 1;
    }
    
    fn update(&mut self) {
        let elapsed = self.window_start.elapsed().as_secs_f64();
        if elapsed >= 1.0 {
            self.rate = self.count as f64 / elapsed;
            self.window_start = Instant::now();
            self.count = 0;
        }
    }
}

/// Agent state for monitoring AI activity
#[derive(Debug, Clone)]
struct AgentState {
    is_thinking: bool,
    current_tool: Option<String>,
    tool_calls_total: u64,
    thinking_start: Option<Instant>,
}

impl Default for AgentState {
    fn default() -> Self {
        Self {
            is_thinking: false,
            current_tool: None,
            tool_calls_total: 0,
            thinking_start: None,
        }
    }
}

/// Dashboard state
pub struct Dashboard {
    service_leds: HashMap<ServiceCategory, Led>,
    connection_led: Led,
    upstream_led: Led,
    capture_led: Led,
    activity_log: Vec<ActivityEntry>,
    max_activity: usize,
    active_connections: usize,
    total_requests: u64,
    error_count: u64,
    start_time: Instant,
    running: Arc<AtomicBool>,
    in_flight: HashMap<u64, InFlightRequest>,
    streaming_count: usize,
    bytes_in: u64,
    bytes_out: u64,
    latency_stats: LatencyStats,
    pool_connections: usize,
    // New metrics
    error_breakdown: HashMap<ErrorType, u64>,
    rate_tracker: RateTracker,
    queue_by_category: HashMap<ServiceCategory, usize>,
    // Agent monitoring
    agent_state: AgentState,
    // Memory management
    last_cleanup: Instant,
}

impl Dashboard {
    pub fn new() -> Self {
        let mut service_leds = HashMap::new();
        let mut queue_by_category = HashMap::new();
        for cat in [
            ServiceCategory::Chat,
            ServiceCategory::Ai,
            ServiceCategory::Queue,
            ServiceCategory::Telemetry,
            ServiceCategory::System,
            ServiceCategory::Unknown,
        ] {
            service_leds.insert(cat, Led::new());
            queue_by_category.insert(cat, 0);
        }
        
        Self {
            service_leds,
            connection_led: Led::new(),
            upstream_led: Led::new(),
            capture_led: Led::new(),
            activity_log: Vec::new(),
            max_activity: 6,
            active_connections: 0,
            total_requests: 0,
            error_count: 0,
            start_time: Instant::now(),
            running: Arc::new(AtomicBool::new(true)),
            in_flight: HashMap::new(),
            streaming_count: 0,
            bytes_in: 0,
            bytes_out: 0,
            latency_stats: LatencyStats::new(100),
            pool_connections: 0,
            error_breakdown: HashMap::new(),
            rate_tracker: RateTracker::new(),
            queue_by_category,
            agent_state: AgentState::default(),
            last_cleanup: Instant::now(),
        }
    }
    
    /// Clean up stale in-flight requests and reset counters to prevent unbounded growth
    fn cleanup_stale_state(&mut self) {
        // Only cleanup every 30 seconds
        if self.last_cleanup.elapsed() < Duration::from_secs(30) {
            return;
        }
        self.last_cleanup = Instant::now();
        
        // Remove stale in-flight requests
        let now = Instant::now();
        let stale_threshold = Duration::from_secs(MAX_IN_FLIGHT_AGE_SECS);
        
        let stale_ids: Vec<u64> = self.in_flight.iter()
            .filter(|(_, req)| now.duration_since(req.started) > stale_threshold)
            .map(|(id, _)| *id)
            .collect();
        
        for id in &stale_ids {
            if let Some(req) = self.in_flight.remove(id) {
                // Decrement streaming count if this was a streaming request
                if req.path.contains("Stream") {
                    self.streaming_count = self.streaming_count.saturating_sub(1);
                }
                // Decrement queue count
                if let Some(count) = self.queue_by_category.get_mut(&req.category) {
                    *count = count.saturating_sub(1);
                }
            }
        }
        
        if !stale_ids.is_empty() {
            tracing::debug!("Cleaned up {} stale in-flight requests", stale_ids.len());
        }
        
        // Force trim in_flight if it's too large (prevent unbounded growth)
        if self.in_flight.len() > MAX_IN_FLIGHT_ENTRIES {
            // Remove oldest entries
            let mut entries: Vec<_> = self.in_flight.iter()
                .map(|(id, req)| (*id, req.started))
                .collect();
            entries.sort_by_key(|(_, started)| *started);
            
            let to_remove = self.in_flight.len() - MAX_IN_FLIGHT_ENTRIES / 2;
            for (id, _) in entries.into_iter().take(to_remove) {
                self.in_flight.remove(&id);
            }
            tracing::warn!("Force-trimmed in_flight map due to size overflow");
        }
        
        // Reset LED activity counts every 5 minutes to prevent u32 overflow
        // and keep the activity bars meaningful
        if self.start_time.elapsed().as_secs() % 300 < 30 {
            for led in self.service_leds.values_mut() {
                // Decay activity count rather than reset to preserve recent info
                led.activity_count = led.activity_count.saturating_sub(led.activity_count / 2);
            }
        }
    }
    
    fn handle_event(&mut self, event: &ProxyEvent) {
        match event {
            ProxyEvent::ConnectionOpened { .. } => {
                self.active_connections += 1;
                self.connection_led.trigger(LedState::Active);
            }
            ProxyEvent::ConnectionClosed { .. } => {
                self.active_connections = self.active_connections.saturating_sub(1);
            }
            ProxyEvent::RequestStarted { request_id, path, endpoint, .. } => {
                let category = ServiceCategory::from_path(path);
                let is_streaming = path.contains("Stream");
                
                self.in_flight.insert(*request_id, InFlightRequest {
                    path: path.clone(),
                    category,
                    endpoint: endpoint.clone(),
                    started: Instant::now(),
                });
                
                // Update queue
                *self.queue_by_category.entry(category).or_insert(0) += 1;
                
                if is_streaming {
                    self.streaming_count += 1;
                }
                
                if let Some(led) = self.service_leds.get_mut(&category) {
                    let state = if is_streaming { LedState::Streaming } else { LedState::Active };
                    led.trigger(state);
                }
                self.total_requests += 1;
                self.rate_tracker.tick();
            }
            ProxyEvent::RequestCompleted { request_id, status, duration_ms, request_size, response_size, .. } => {
                self.bytes_out += *request_size as u64;
                if let Some(size) = response_size {
                    self.bytes_in += *size as u64;
                }
                self.latency_stats.add(*duration_ms);
                
                let (category, endpoint, is_streaming) = if let Some(req) = self.in_flight.remove(request_id) {
                    let is_streaming = req.path.contains("Stream");
                    if is_streaming {
                        self.streaming_count = self.streaming_count.saturating_sub(1);
                    }
                    // Update queue
                    if let Some(count) = self.queue_by_category.get_mut(&req.category) {
                        *count = count.saturating_sub(1);
                    }
                    (req.category, req.endpoint, is_streaming)
                } else {
                    (ServiceCategory::Unknown, "unknown".to_string(), false)
                };
                
                if let Some(led) = self.service_leds.get_mut(&category) {
                    let state = if *status >= 400 {
                        self.error_count += 1;
                        *self.error_breakdown.entry(ErrorType::Upstream).or_insert(0) += 1;
                        LedState::Error
                    } else {
                        LedState::Success
                    };
                    led.trigger(state);
                }
                
                self.activity_log.push(ActivityEntry {
                    timestamp: Instant::now(),
                    category,
                    endpoint,
                    status: Some(*status),
                    duration_ms: Some(*duration_ms),
                    is_streaming,
                });
                
                while self.activity_log.len() > self.max_activity {
                    self.activity_log.remove(0);
                }
            }
            ProxyEvent::RequestFailed { request_id, error, .. } => {
                let error_type = ErrorType::from_error(error);
                *self.error_breakdown.entry(error_type).or_insert(0) += 1;
                
                let category = if let Some(req) = self.in_flight.remove(request_id) {
                    if req.path.contains("Stream") {
                        self.streaming_count = self.streaming_count.saturating_sub(1);
                    }
                    if let Some(count) = self.queue_by_category.get_mut(&req.category) {
                        *count = count.saturating_sub(1);
                    }
                    req.category
                } else {
                    ServiceCategory::Unknown
                };
                
                if let Some(led) = self.service_leds.get_mut(&category) {
                    led.trigger(LedState::Error);
                }
                self.error_count += 1;
            }
            ProxyEvent::UpstreamConnection { action, pool_size, .. } => {
                self.pool_connections = *pool_size;
                use crate::events::UpstreamAction;
                let state = match action {
                    UpstreamAction::Connected => LedState::Success,
                    UpstreamAction::Reused => LedState::Active,
                    UpstreamAction::Disconnected => LedState::Idle,
                    UpstreamAction::Failed { .. } => LedState::Error,
                };
                self.upstream_led.trigger(state);
            }
            ProxyEvent::CaptureSaved { size, .. } => {
                self.bytes_out += *size as u64;
                self.capture_led.trigger(LedState::Success);
            }
            ProxyEvent::AgentActivity { activity, tool_name, .. } => {
                match activity {
                    AgentActivityType::Thinking => {
                        self.agent_state.is_thinking = true;
                        self.agent_state.thinking_start = Some(Instant::now());
                    }
                    AgentActivityType::ToolCallStarted => {
                        self.agent_state.current_tool = tool_name.clone();
                        self.agent_state.tool_calls_total += 1;
                    }
                    AgentActivityType::ToolCallCompleted => {
                        self.agent_state.current_tool = None;
                    }
                    AgentActivityType::WaitingForUser => {
                        self.agent_state.is_thinking = false;
                        self.agent_state.thinking_start = None;
                    }
                    AgentActivityType::CodeGeneration => {
                        // Could track this separately
                    }
                }
            }
            _ => {}
        }
    }
    
    fn decay_leds(&mut self, decay_rate: f32) {
        for led in self.service_leds.values_mut() {
            led.decay(decay_rate);
        }
        self.connection_led.decay(decay_rate);
        self.upstream_led.decay(decay_rate);
        self.capture_led.decay(decay_rate);
    }
    
    fn format_bytes(bytes: u64) -> String {
        if bytes < 1024 {
            format!("{}B", bytes)
        } else if bytes < 1024 * 1024 {
            format!("{:.1}K", bytes as f64 / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            format!("{:.1}M", bytes as f64 / (1024.0 * 1024.0))
        } else {
            format!("{:.2}G", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
        }
    }
    
    fn longest_in_flight(&self) -> Option<(&InFlightRequest, Duration)> {
        self.in_flight.values()
            .map(|req| (req, req.started.elapsed()))
            .max_by_key(|(_, dur)| *dur)
    }
    
    fn render(&self) -> String {
        use colors::*;
        let mut out = String::new();
        
        // Clear screen
        out.push_str("\x1b[2J\x1b[H");
        
        let width = 72;
        let border_h = "═".repeat(width - 2);
        
        // Header
        out.push_str(&format!("{BOLD}{BORDER}╔{border_h}╗{RESET}\n"));
        out.push_str(&format!("{BOLD}{BORDER}║{RESET}  {BOLD}{HEADER}CURSOR PROXY DASHBOARD{RESET}"));
        out.push_str(&format!("{:>46}{BOLD}{BORDER}║{RESET}\n", ""));
        out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        
        // Status row
        let uptime = self.start_time.elapsed().as_secs();
        let uptime_str = format!("{}h {:02}m {:02}s", uptime / 3600, (uptime % 3600) / 60, uptime % 60);
        self.rate_tracker.clone().update();
        
        out.push_str(&format!(
            "{BOLD}{BORDER}║{RESET} {} {LABEL}CONN{RESET}  {} {LABEL}UP{RESET}  {} {LABEL}CAP{RESET}  {LABEL}│{RESET} {LABEL}Uptime:{RESET} {VALUE}{:<14}{RESET}     {BOLD}{BORDER}║{RESET}\n",
            self.connection_led.render(),
            self.upstream_led.render(),
            self.capture_led.render(),
            uptime_str
        ));
        
        let streaming_indicator = if self.streaming_count > 0 {
            format!("{STREAMING}⚡{}{RESET}", self.streaming_count)
        } else {
            format!("{LABEL}⚡0{RESET}")
        };
        
        out.push_str(&format!(
            "{BOLD}{BORDER}║{RESET} {LABEL}Active:{RESET} {VALUE}{:<3}{RESET}  {LABEL}Reqs:{RESET} {VALUE}{:<6}{RESET}  {LABEL}Err:{RESET} {ERROR}{:<4}{RESET}  {} {LABEL}Stream{RESET}  {LABEL}Rate:{RESET}{VALUE}{:>5.1}/s{RESET} {BOLD}{BORDER}║{RESET}\n",
            self.active_connections,
            self.total_requests,
            self.error_count,
            streaming_indicator,
            self.rate_tracker.rate
        ));
        
        out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        
        // Metrics row
        let p50 = self.latency_stats.percentile(50.0).map(|v| format!("{}ms", v)).unwrap_or("--".into());
        let p99 = self.latency_stats.percentile(99.0).map(|v| format!("{}ms", v)).unwrap_or("--".into());
        let avg = self.latency_stats.avg().map(|v| format!("{}ms", v)).unwrap_or("--".into());
        
        out.push_str(&format!(
            "{BOLD}{BORDER}║{RESET} {LABEL}Latency:{RESET} {LABEL}p50={RESET}{WARNING}{:<6}{RESET} {LABEL}p99={RESET}{WARNING}{:<6}{RESET} {LABEL}avg={RESET}{WARNING}{:<6}{RESET} {LABEL}Pool:{RESET}{AI}{}{RESET}       {BOLD}{BORDER}║{RESET}\n",
            p50, p99, avg, self.pool_connections
        ));
        
        out.push_str(&format!(
            "{BOLD}{BORDER}║{RESET} {LABEL}Traffic:{RESET} {SUCCESS}↓{:<8}{RESET} {BLUE}↑{:<8}{RESET}                               {BOLD}{BORDER}║{RESET}\n",
            Self::format_bytes(self.bytes_in),
            Self::format_bytes(self.bytes_out),
        ));
        
        out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        
        // Error breakdown (if any errors)
        if self.error_count > 0 {
            out.push_str(&format!("{BOLD}{BORDER}║{RESET} {BOLD}{HEADER}ERRORS{RESET}"));
            let mut err_parts = Vec::new();
            for (err_type, count) in &self.error_breakdown {
                if *count > 0 {
                    err_parts.push(format!("{}{}: {}{RESET}", err_type.color(), err_type.name(), count));
                }
            }
            let err_str = err_parts.join("  ");
            out.push_str(&format!(" {:<60}{BOLD}{BORDER}║{RESET}\n", err_str));
            out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        }
        
        // Agent state (when active)
        if self.streaming_count > 0 || self.agent_state.is_thinking || self.agent_state.current_tool.is_some() {
            out.push_str(&format!("{BOLD}{BORDER}║{RESET} {BOLD}{HEADER}AGENT{RESET} "));
            
            let thinking_indicator = if self.agent_state.is_thinking {
                let secs = self.agent_state.thinking_start
                    .map(|t| t.elapsed().as_secs())
                    .unwrap_or(0);
                format!("{STREAMING}◉ Thinking{RESET} {LABEL}{}s{RESET}", secs)
            } else {
                format!("{LABEL}○ Idle{RESET}")
            };
            
            let tool_indicator = if let Some(tool) = &self.agent_state.current_tool {
                format!("  {WARNING}⚙ {}{RESET}", truncate(tool, 20))
            } else {
                String::new()
            };
            
            out.push_str(&format!(
                "{}{}  {LABEL}Tools:{RESET} {}",
                thinking_indicator,
                tool_indicator,
                self.agent_state.tool_calls_total
            ));
            out.push_str(&format!("{:>24}{BOLD}{BORDER}║{RESET}\n", ""));
            out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        }
        
        // Request Queue
        out.push_str(&format!("{BOLD}{BORDER}║{RESET} {BOLD}{HEADER}REQUEST QUEUE{RESET} "));
        let total_queued: usize = self.queue_by_category.values().sum();
        out.push_str(&format!("{LABEL}({} in-flight){RESET}", total_queued));
        out.push_str(&format!("{:>40}{BOLD}{BORDER}║{RESET}\n", ""));
        
        let services = [
            (ServiceCategory::Chat, "Chat", CHAT),
            (ServiceCategory::Ai, "AI", AI),
            (ServiceCategory::Queue, "Queue", QUEUE),
            (ServiceCategory::Telemetry, "Telem", TELEMETRY),
            (ServiceCategory::System, "Sys", SYSTEM),
        ];
        
        out.push_str(&format!("{BOLD}{BORDER}║{RESET} "));
        for (cat, name, color) in &services {
            let count = self.queue_by_category.get(cat).copied().unwrap_or(0);
            let led = self.service_leds.get(cat).unwrap();
            out.push_str(&format!("{} {}{:<5}{RESET}:{:<2} ", led.render(), color, name, count));
        }
        out.push_str(&format!("         {BOLD}{BORDER}║{RESET}\n"));
        
        // Activity bars
        out.push_str(&format!("{BOLD}{BORDER}║{RESET} "));
        for (cat, _, color) in &services {
            let led = self.service_leds.get(cat).unwrap();
            let bar = render_activity_bar(led.activity_count, 6, color);
            out.push_str(&format!("{}  ", bar));
        }
        out.push_str(&format!("           {BOLD}{BORDER}║{RESET}\n"));
        
        out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
        
        // Hang detection
        if let Some((req, duration)) = self.longest_in_flight() {
            if duration.as_secs() >= 5 {
                let hang_color = if duration.as_secs() >= 30 { ERROR } else { WARNING };
                out.push_str(&format!(
                    "{BOLD}{BORDER}║{RESET} {hang_color}⚠ LONG REQUEST:{RESET} {LABEL}{:.30}{RESET} {hang_color}{}s{RESET}",
                    req.endpoint,
                    duration.as_secs()
                ));
                out.push_str(&format!("{:>23}{BOLD}{BORDER}║{RESET}\n", ""));
                out.push_str(&format!("{BOLD}{BORDER}╠{border_h}╣{RESET}\n"));
            }
        }
        
        // Activity log
        out.push_str(&format!("{BOLD}{BORDER}║{RESET} {BOLD}{HEADER}RECENT ACTIVITY{RESET}"));
        out.push_str(&format!("{:>53}{BOLD}{BORDER}║{RESET}\n", ""));
        
        for entry in self.activity_log.iter().rev().take(6) {
            let status_icon = match entry.status {
                Some(s) if s < 300 => format!("{SUCCESS}✓{RESET}"),
                Some(s) if s < 400 => format!("{WARNING}◐{RESET}"),
                Some(_) => format!("{ERROR}✗{RESET}"),
                None => format!("{LABEL}?{RESET}"),
            };
            
            let duration_str = entry.duration_ms
                .map(|d| format!("{}ms", d))
                .unwrap_or_else(|| "...".to_string());
            
            let stream_icon = if entry.is_streaming { format!("{STREAMING}⚡{RESET}") } else { " ".to_string() };
            let cat_color = entry.category.color();
            
            out.push_str(&format!(
                "{BOLD}{BORDER}║{RESET}  {}{:<9}{RESET} {:<32} {:>6} {}{}{BOLD}{BORDER}║{RESET}\n",
                cat_color,
                entry.category.name(),
                truncate(&entry.endpoint, 32),
                duration_str,
                status_icon,
                stream_icon
            ));
        }
        
        for _ in self.activity_log.len()..6 {
            out.push_str(&format!("{BOLD}{BORDER}║{RESET}{:>70}{BOLD}{BORDER}║{RESET}\n", ""));
        }
        
        out.push_str(&format!("{BOLD}{BORDER}╚{border_h}╝{RESET}\n"));
        out.push_str(&format!("\n{LABEL}Press Ctrl+C to exit{RESET}\n"));
        
        out
    }
    
    pub async fn run(&mut self, mut receiver: EventReceiver) {
        let mut render_interval = interval(Duration::from_millis(50));
        let decay_rate = 0.02;
        
        let running = self.running.clone();
        
        let running_clone = running.clone();
        tokio::spawn(async move {
            tokio::signal::ctrl_c().await.ok();
            running_clone.store(false, Ordering::SeqCst);
        });
        
        while running.load(Ordering::SeqCst) {
            tokio::select! {
                event = receiver.recv() => {
                    if let Some(event) = event {
                        self.handle_event(&event);
                    } else {
                        break;
                    }
                }
                _ = render_interval.tick() => {
                    self.decay_leds(decay_rate);
                    self.rate_tracker.update();
                    self.cleanup_stale_state(); // Prevent memory leaks
                    
                    let frame = self.render();
                    print!("{}", frame);
                    io::stdout().flush().ok();
                }
            }
        }
        
        print!("\x1b[2J\x1b[H");
        println!("Dashboard stopped.");
    }
    
    /// Export current state for egui rendering
    pub fn export_state(&self) -> DashboardState {
        let mut service_activity = HashMap::new();
        for (cat, led) in &self.service_leds {
            service_activity.insert(*cat, ServiceState {
                activity_count: led.activity_count,
                brightness: led.brightness,
                state: match led.state {
                    LedState::Idle => "idle",
                    LedState::Active => "active",
                    LedState::Success => "success",
                    LedState::Error => "error",
                    LedState::Streaming => "streaming",
                },
                queue_size: self.queue_by_category.get(cat).copied().unwrap_or(0),
            });
        }
        
        let recent_activity: Vec<ActivityRecord> = self.activity_log.iter().rev().take(10).map(|e| {
            ActivityRecord {
                category: e.category.name().to_string(),
                endpoint: e.endpoint.clone(),
                status: e.status,
                duration_ms: e.duration_ms,
                is_streaming: e.is_streaming,
                age_ms: e.timestamp.elapsed().as_millis() as u64,
            }
        }).collect();
        
        let error_breakdown: HashMap<String, u64> = self.error_breakdown.iter()
            .map(|(k, v)| (k.name().to_string(), *v))
            .collect();
        
        let longest_request = self.longest_in_flight()
            .map(|(req, dur)| (req.endpoint.clone(), dur.as_secs()));
        
        let agent_thinking_secs = self.agent_state.thinking_start
            .map(|t| t.elapsed().as_secs());
        
        DashboardState {
            active_connections: self.active_connections,
            total_requests: self.total_requests,
            error_count: self.error_count,
            streaming_count: self.streaming_count,
            bytes_in: self.bytes_in,
            bytes_out: self.bytes_out,
            latency_p50: self.latency_stats.percentile(50.0),
            latency_p99: self.latency_stats.percentile(99.0),
            latency_avg: self.latency_stats.avg(),
            pool_connections: self.pool_connections,
            uptime_secs: self.start_time.elapsed().as_secs(),
            service_activity,
            recent_activity,
            error_breakdown,
            request_rate: self.rate_tracker.rate,
            longest_request,
            agent_is_thinking: self.agent_state.is_thinking,
            agent_current_tool: self.agent_state.current_tool.clone(),
            agent_tool_calls: self.agent_state.tool_calls_total,
            agent_thinking_secs,
        }
    }
}

fn render_activity_bar(count: u32, max_width: usize, color: &str) -> String {
    let filled = (count as usize).min(max_width);
    let empty = max_width.saturating_sub(filled);
    format!(
        "{LABEL}[{color}{}{LABEL}{}{LABEL}]{RESET}",
        "█".repeat(filled),
        "░".repeat(empty),
        LABEL = colors::BRIGHT_BLACK,
        RESET = colors::RESET,
    )
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max { s.to_string() } else { format!("{}…", &s[..max-1]) }
}

impl Default for Dashboard {
    fn default() -> Self { Self::new() }
}

// ============================================================================
// Shared dashboard state for egui integration
// ============================================================================

#[derive(Debug, Clone)]
pub struct DashboardState {
    pub active_connections: usize,
    pub total_requests: u64,
    pub error_count: u64,
    pub streaming_count: usize,
    pub bytes_in: u64,
    pub bytes_out: u64,
    pub latency_p50: Option<u64>,
    pub latency_p99: Option<u64>,
    pub latency_avg: Option<u64>,
    pub pool_connections: usize,
    pub uptime_secs: u64,
    pub service_activity: HashMap<ServiceCategory, ServiceState>,
    pub recent_activity: Vec<ActivityRecord>,
    pub error_breakdown: HashMap<String, u64>,
    pub request_rate: f64,
    pub longest_request: Option<(String, u64)>,
    // Agent monitoring
    pub agent_is_thinking: bool,
    pub agent_current_tool: Option<String>,
    pub agent_tool_calls: u64,
    pub agent_thinking_secs: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct ServiceState {
    pub activity_count: u32,
    pub brightness: f32,
    pub state: &'static str,
    pub queue_size: usize,
}

#[derive(Debug, Clone)]
pub struct ActivityRecord {
    pub category: String,
    pub endpoint: String,
    pub status: Option<u16>,
    pub duration_ms: Option<u64>,
    pub is_streaming: bool,
    pub age_ms: u64,
}


