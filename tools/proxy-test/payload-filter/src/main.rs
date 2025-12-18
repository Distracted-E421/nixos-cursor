//! Payload Filter - Lightning-fast Cursor API payload filtering
//!
//! Filters and analyzes captured Cursor API payloads with sub-millisecond performance.
//!
//! Usage:
//!     payload-filter stats                           # Overall statistics
//!     payload-filter filter --service AiService      # Filter by service
//!     payload-filter filter --endpoint CheckQueue    # Filter by endpoint
//!     payload-filter filter --exclude-noise          # Exclude telemetry
//!     payload-filter unique                          # Show unique payloads only
//!     payload-filter decode <file.bin>               # Decode protobuf payload

use clap::{Parser, Subcommand};
use fnv::FnvHashMap;
use rayon::prelude::*;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;
use walkdir::WalkDir;

/// Cursor API Payload Filter - Lightning-fast filtering and analysis
#[derive(Parser)]
#[command(name = "payload-filter")]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Path to payload database
    #[arg(short, long, default_value = "../payload-db")]
    db: PathBuf,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Show database statistics
    Stats,
    
    /// Filter payloads by criteria
    Filter {
        /// Filter by service (substring match)
        #[arg(short, long)]
        service: Option<String>,
        
        /// Filter by endpoint (substring match)
        #[arg(short, long)]
        endpoint: Option<String>,
        
        /// Exclude noise services (Analytics, tev1, api)
        #[arg(long)]
        exclude_noise: bool,
        
        /// Only show high-priority services
        #[arg(long)]
        high_priority: bool,
        
        /// Minimum payload size in bytes
        #[arg(long)]
        min_size: Option<usize>,
        
        /// Maximum payload size in bytes
        #[arg(long)]
        max_size: Option<usize>,
        
        /// Limit results
        #[arg(short, long)]
        limit: Option<usize>,
        
        /// Output format (summary, paths, json)
        #[arg(short, long, default_value = "summary")]
        output: String,
    },
    
    /// Show unique payloads (deduplicated by hash)
    Unique {
        /// Only show high-priority services
        #[arg(long)]
        high_priority: bool,
        
        /// Exclude noise
        #[arg(long)]
        exclude_noise: bool,
    },
    
    /// Decode a protobuf binary payload
    Decode {
        /// Path to .bin file
        file: PathBuf,
        
        /// Output as JSON
        #[arg(long)]
        json: bool,
    },
    
    /// Analyze field patterns across payloads
    Fields {
        /// Filter by service
        #[arg(short, long)]
        service: Option<String>,
        
        /// Filter by endpoint
        #[arg(short, long)]
        endpoint: Option<String>,
    },
}

/// Payload metadata from JSON files
#[derive(Debug, Deserialize, Serialize)]
struct PayloadMetadata {
    filename: String,
    timestamp: String,
    cursor_version: String,
    direction: String,
    service: String,
    endpoint: String,
    full_path: String,
    host: String,
    method: String,
    content_length: usize,
    content_hash_sha256: String,
    #[serde(default)]
    grpc_messages: Vec<serde_json::Value>,
}

/// Noise services to filter out
const NOISE_SERVICES: &[&str] = &[
    "aiserver.v1.AnalyticsService",
    "tev1",
    "api",
];

/// High-priority services for AI operations
const HIGH_PRIORITY_SERVICES: &[&str] = &[
    "aiserver.v1.AiService",
    "aiserver.v1.ChatService",
    "aiserver.v1.BackgroundComposerService",
    "aiserver.v1.FastApplyService",
];

/// Load all metadata files from the database
fn load_metadata(db_path: &Path) -> Vec<(PathBuf, PayloadMetadata)> {
    let start = Instant::now();
    
    let json_files: Vec<PathBuf> = WalkDir::new(db_path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path().extension().map_or(false, |ext| ext == "json")
                && !e.file_name().to_string_lossy().starts_with("session_")
        })
        .map(|e| e.path().to_path_buf())
        .collect();
    
    eprintln!("Found {} JSON files in {:?}", json_files.len(), start.elapsed());
    
    let start = Instant::now();
    let metadata: Vec<(PathBuf, PayloadMetadata)> = json_files
        .par_iter()
        .filter_map(|path| {
            let content = fs::read_to_string(path).ok()?;
            let meta: PayloadMetadata = serde_json::from_str(&content).ok()?;
            Some((path.clone(), meta))
        })
        .collect();
    
    eprintln!("Loaded {} metadata records in {:?}", metadata.len(), start.elapsed());
    metadata
}

/// Check if a service is noise
fn is_noise(service: &str) -> bool {
    NOISE_SERVICES.iter().any(|n| service.contains(n))
}

/// Check if a service is high-priority
fn is_high_priority(service: &str) -> bool {
    HIGH_PRIORITY_SERVICES.iter().any(|h| service.contains(h))
}

/// Print statistics
fn cmd_stats(db_path: &Path) {
    let metadata = load_metadata(db_path);
    
    let start = Instant::now();
    
    let total = metadata.len();
    let total_size: usize = metadata.iter().map(|(_, m)| m.content_length).sum();
    
    // Count by service
    let mut by_service: FnvHashMap<String, usize> = FnvHashMap::default();
    let mut by_endpoint: FnvHashMap<String, usize> = FnvHashMap::default();
    let mut by_version: FnvHashMap<String, usize> = FnvHashMap::default();
    let mut unique_hashes: HashSet<String> = HashSet::new();
    
    for (_, m) in &metadata {
        *by_service.entry(m.service.clone()).or_insert(0) += 1;
        *by_endpoint.entry(m.endpoint.clone()).or_insert(0) += 1;
        *by_version.entry(m.cursor_version.clone()).or_insert(0) += 1;
        unique_hashes.insert(m.content_hash_sha256.clone());
    }
    
    println!("╔══════════════════════════════════════════════════════════════════╗");
    println!("║               PAYLOAD DATABASE STATISTICS                        ║");
    println!("╠══════════════════════════════════════════════════════════════════╣");
    println!("║ Total payloads:  {:>10}                                     ║", total);
    println!("║ Unique payloads: {:>10}                                     ║", unique_hashes.len());
    println!("║ Total data:      {:>10.2} MB                                   ║", total_size as f64 / 1024.0 / 1024.0);
    println!("╠══════════════════════════════════════════════════════════════════╣");
    
    // Services by count
    let mut services: Vec<_> = by_service.iter().collect();
    services.sort_by(|a, b| b.1.cmp(a.1));
    
    println!("║ BY SERVICE:                                                      ║");
    for (service, count) in services.iter().take(15) {
        let priority = if is_high_priority(service) { "🟢" } 
                      else if is_noise(service) { "🔴" } 
                      else { "⚪" };
        let pct = **count as f64 / total as f64 * 100.0;
        println!("║ {} {:45} {:>6} ({:>5.1}%) ║", priority, service, count, pct);
    }
    
    println!("╠══════════════════════════════════════════════════════════════════╣");
    println!("║ BY ENDPOINT (top 15):                                            ║");
    
    let mut endpoints: Vec<_> = by_endpoint.iter().collect();
    endpoints.sort_by(|a, b| b.1.cmp(a.1));
    
    for (endpoint, count) in endpoints.iter().take(15) {
        let pct = **count as f64 / total as f64 * 100.0;
        println!("║   {:50} {:>6} ({:>5.1}%) ║", endpoint, count, pct);
    }
    
    println!("╠══════════════════════════════════════════════════════════════════╣");
    println!("║ BY VERSION:                                                      ║");
    for (version, count) in &by_version {
        println!("║   {:50} {:>6}        ║", version, count);
    }
    
    // Noise stats
    let noise_count: usize = metadata.iter()
        .filter(|(_, m)| is_noise(&m.service))
        .count();
    let high_priority_count: usize = metadata.iter()
        .filter(|(_, m)| is_high_priority(&m.service))
        .count();
    
    println!("╠══════════════════════════════════════════════════════════════════╣");
    println!("║ SUMMARY:                                                         ║");
    println!("║   🔴 Noise (telemetry): {:>6} ({:>5.1}%)                          ║", 
             noise_count, noise_count as f64 / total as f64 * 100.0);
    println!("║   🟢 High-priority:     {:>6} ({:>5.1}%)                          ║",
             high_priority_count, high_priority_count as f64 / total as f64 * 100.0);
    println!("╚══════════════════════════════════════════════════════════════════╝");
    
    eprintln!("Analysis completed in {:?}", start.elapsed());
}

/// Filter payloads
fn cmd_filter(
    db_path: &Path,
    service: Option<String>,
    endpoint: Option<String>,
    exclude_noise: bool,
    high_priority: bool,
    min_size: Option<usize>,
    max_size: Option<usize>,
    limit: Option<usize>,
    output: String,
) {
    let metadata = load_metadata(db_path);
    let start = Instant::now();
    
    let service_re = service.as_ref().map(|s| Regex::new(&format!("(?i){}", s)).unwrap());
    let endpoint_re = endpoint.as_ref().map(|e| Regex::new(&format!("(?i){}", e)).unwrap());
    
    let filtered: Vec<&(PathBuf, PayloadMetadata)> = metadata
        .par_iter()
        .filter(|(_, m)| {
            // Service filter
            if let Some(ref re) = service_re {
                if !re.is_match(&m.service) {
                    return false;
                }
            }
            
            // Endpoint filter
            if let Some(ref re) = endpoint_re {
                if !re.is_match(&m.endpoint) {
                    return false;
                }
            }
            
            // Noise filter
            if exclude_noise && is_noise(&m.service) {
                return false;
            }
            
            // High priority filter
            if high_priority && !is_high_priority(&m.service) {
                return false;
            }
            
            // Size filters
            if let Some(min) = min_size {
                if m.content_length < min {
                    return false;
                }
            }
            if let Some(max) = max_size {
                if m.content_length > max {
                    return false;
                }
            }
            
            true
        })
        .collect();
    
    let count = filtered.len();
    let limited: Vec<_> = match limit {
        Some(l) => filtered.into_iter().take(l).collect(),
        None => filtered,
    };
    
    eprintln!("Filtered to {} payloads in {:?}", count, start.elapsed());
    
    match output.as_str() {
        "paths" => {
            for (path, _) in &limited {
                println!("{}", path.display());
            }
        }
        "json" => {
            let json_output: Vec<_> = limited.iter()
                .map(|(_, m)| m)
                .collect();
            println!("{}", serde_json::to_string_pretty(&json_output).unwrap());
        }
        _ => {
            // Summary output
            println!("╔════════════════════════════════════════════════════════════════╗");
            println!("║ FILTER RESULTS: {} payloads{}", count,
                     limit.map_or(String::new(), |l| format!(" (showing {})", l.min(count))));
            println!("╠════════════════════════════════════════════════════════════════╣");
            
            // Group by service/endpoint
            let mut by_ep: HashMap<String, Vec<&PayloadMetadata>> = HashMap::new();
            for (_, m) in &limited {
                let key = format!("{}/{}", m.service, m.endpoint);
                by_ep.entry(key).or_default().push(m);
            }
            
            let mut eps: Vec<_> = by_ep.iter().collect();
            eps.sort_by(|a, b| b.1.len().cmp(&a.1.len()));
            
            for (ep, payloads) in eps.iter().take(20) {
                let sizes: Vec<_> = payloads.iter().map(|p| p.content_length).collect();
                let min_size = sizes.iter().min().unwrap_or(&0);
                let max_size = sizes.iter().max().unwrap_or(&0);
                let avg_size = sizes.iter().sum::<usize>() / sizes.len().max(1);
                
                println!("║ {:50} {:>5}   ║", ep, payloads.len());
                println!("║   Size: {:>6}-{:>6} bytes (avg: {:>6})                  ║", 
                         min_size, max_size, avg_size);
            }
            println!("╚════════════════════════════════════════════════════════════════╝");
        }
    }
}

/// Show unique payloads
fn cmd_unique(db_path: &Path, high_priority: bool, exclude_noise: bool) {
    let metadata = load_metadata(db_path);
    let start = Instant::now();
    
    // Group by hash
    let mut by_hash: HashMap<String, Vec<&PayloadMetadata>> = HashMap::new();
    for (_, m) in &metadata {
        if exclude_noise && is_noise(&m.service) {
            continue;
        }
        if high_priority && !is_high_priority(&m.service) {
            continue;
        }
        by_hash.entry(m.content_hash_sha256.clone()).or_default().push(m);
    }
    
    println!("╔════════════════════════════════════════════════════════════════╗");
    println!("║ UNIQUE PAYLOADS: {}                                             ║", by_hash.len());
    println!("╠════════════════════════════════════════════════════════════════╣");
    
    // Group unique by endpoint
    let mut by_ep: HashMap<String, usize> = HashMap::new();
    for payloads in by_hash.values() {
        let key = format!("{}/{}", payloads[0].service, payloads[0].endpoint);
        *by_ep.entry(key).or_insert(0) += 1;
    }
    
    let mut eps: Vec<_> = by_ep.iter().collect();
    eps.sort_by(|a, b| b.1.cmp(a.1));
    
    for (ep, count) in eps.iter().take(25) {
        let priority = if HIGH_PRIORITY_SERVICES.iter().any(|h| ep.contains(h)) { "🟢" } else { "⚪" };
        println!("║ {} {:50} {:>5}   ║", priority, ep, count);
    }
    
    println!("╚════════════════════════════════════════════════════════════════╝");
    eprintln!("Deduplication completed in {:?}", start.elapsed());
}

/// Decode protobuf payload
fn cmd_decode(file: &Path, json_output: bool) {
    let data = fs::read(file).expect("Failed to read file");
    let fields = decode_protobuf(&data);
    
    if json_output {
        println!("{}", serde_json::to_string_pretty(&fields).unwrap());
    } else {
        println!("Decoded {} bytes:", data.len());
        print_fields(&fields, 0);
    }
}

/// Protobuf field
#[derive(Debug, Serialize)]
struct ProtoField {
    field_number: u32,
    wire_type: u8,
    wire_type_name: String,
    value: ProtoValue,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum ProtoValue {
    Varint(u64),
    Fixed64(u64),
    Fixed32(u32),
    String(String),
    Bytes(String), // hex
    Nested(Vec<ProtoField>),
}

/// Decode protobuf wire format
fn decode_protobuf(data: &[u8]) -> Vec<ProtoField> {
    let mut fields = Vec::new();
    let mut offset = 0;
    
    while offset < data.len() {
        // Read tag
        let (tag, new_offset) = match read_varint(data, offset) {
            Some(v) => v,
            None => break,
        };
        offset = new_offset;
        
        let wire_type = (tag & 0x07) as u8;
        let field_number = (tag >> 3) as u32;
        
        if field_number == 0 {
            break;
        }
        
        let wire_type_name = match wire_type {
            0 => "varint",
            1 => "fixed64",
            2 => "length_delimited",
            5 => "fixed32",
            _ => "unknown",
        }.to_string();
        
        let value = match wire_type {
            0 => {
                let (val, new_offset) = match read_varint(data, offset) {
                    Some(v) => v,
                    None => break,
                };
                offset = new_offset;
                ProtoValue::Varint(val)
            }
            1 => {
                if offset + 8 > data.len() {
                    break;
                }
                let val = u64::from_le_bytes(data[offset..offset+8].try_into().unwrap());
                offset += 8;
                ProtoValue::Fixed64(val)
            }
            2 => {
                let (length, new_offset) = match read_varint(data, offset) {
                    Some(v) => v,
                    None => break,
                };
                offset = new_offset;
                let length = length as usize;
                
                if offset + length > data.len() {
                    break;
                }
                
                let content = &data[offset..offset+length];
                offset += length;
                
                // Try as string
                if let Ok(s) = std::str::from_utf8(content) {
                    if s.chars().all(|c| c.is_ascii_graphic() || c.is_ascii_whitespace()) {
                        ProtoValue::String(s.to_string())
                    } else {
                        // Try nested decode
                        let nested = decode_protobuf(content);
                        if !nested.is_empty() {
                            ProtoValue::Nested(nested)
                        } else {
                            ProtoValue::Bytes(hex::encode(&content[..content.len().min(50)]))
                        }
                    }
                } else {
                    // Try nested decode
                    let nested = decode_protobuf(content);
                    if !nested.is_empty() {
                        ProtoValue::Nested(nested)
                    } else {
                        ProtoValue::Bytes(hex::encode(&content[..content.len().min(50)]))
                    }
                }
            }
            5 => {
                if offset + 4 > data.len() {
                    break;
                }
                let val = u32::from_le_bytes(data[offset..offset+4].try_into().unwrap());
                offset += 4;
                ProtoValue::Fixed32(val)
            }
            _ => break,
        };
        
        fields.push(ProtoField {
            field_number,
            wire_type,
            wire_type_name,
            value,
        });
        
        if fields.len() > 1000 {
            break;
        }
    }
    
    fields
}

fn read_varint(data: &[u8], mut offset: usize) -> Option<(u64, usize)> {
    let mut value = 0u64;
    let mut shift = 0;
    
    while offset < data.len() {
        let byte = data[offset];
        value |= ((byte & 0x7F) as u64) << shift;
        offset += 1;
        
        if byte & 0x80 == 0 {
            return Some((value, offset));
        }
        
        shift += 7;
        if shift > 63 {
            return None;
        }
    }
    None
}

fn print_fields(fields: &[ProtoField], indent: usize) {
    let prefix = "  ".repeat(indent);
    
    for field in fields {
        match &field.value {
            ProtoValue::Varint(v) => {
                println!("{}#{} ({}): {}", prefix, field.field_number, field.wire_type_name, v);
            }
            ProtoValue::Fixed64(v) => {
                println!("{}#{} ({}): {}", prefix, field.field_number, field.wire_type_name, v);
            }
            ProtoValue::Fixed32(v) => {
                println!("{}#{} ({}): {}", prefix, field.field_number, field.wire_type_name, v);
            }
            ProtoValue::String(s) => {
                let display = if s.len() > 80 { format!("{}...", &s[..80]) } else { s.clone() };
                println!("{}#{} ({}): \"{}\"", prefix, field.field_number, field.wire_type_name, display);
            }
            ProtoValue::Bytes(hex) => {
                println!("{}#{} ({}): bytes[{}]", prefix, field.field_number, field.wire_type_name, hex);
            }
            ProtoValue::Nested(nested) => {
                println!("{}#{} ({}): <nested>", prefix, field.field_number, field.wire_type_name);
                print_fields(nested, indent + 1);
            }
        }
    }
}

/// Analyze field patterns
fn cmd_fields(db_path: &Path, service: Option<String>, endpoint: Option<String>) {
    let metadata = load_metadata(db_path);
    
    let service_re = service.as_ref().map(|s| Regex::new(&format!("(?i){}", s)).unwrap());
    let endpoint_re = endpoint.as_ref().map(|e| Regex::new(&format!("(?i){}", e)).unwrap());
    
    // Group by endpoint
    let mut by_endpoint: HashMap<String, Vec<&PayloadMetadata>> = HashMap::new();
    
    for (_, m) in &metadata {
        if let Some(ref re) = service_re {
            if !re.is_match(&m.service) {
                continue;
            }
        }
        if let Some(ref re) = endpoint_re {
            if !re.is_match(&m.endpoint) {
                continue;
            }
        }
        
        let key = format!("{}/{}", m.service, m.endpoint);
        by_endpoint.entry(key).or_default().push(m);
    }
    
    println!("╔════════════════════════════════════════════════════════════════╗");
    println!("║ FIELD PATTERN ANALYSIS                                         ║");
    println!("╠════════════════════════════════════════════════════════════════╣");
    
    for (ep, payloads) in by_endpoint.iter() {
        println!("║ {:60} ║", ep);
        println!("║   Samples: {}                                                   ║", payloads.len());
        
        // Analyze grpc_messages if present
        let mut field_counts: HashMap<(u32, String), usize> = HashMap::new();
        
        for m in payloads {
            for msg in &m.grpc_messages {
                if let Some(hints) = msg.get("field_hints").and_then(|h| h.as_array()) {
                    for hint in hints {
                        if let (Some(fn_num), Some(wt)) = (
                            hint.get("field_number").and_then(|n| n.as_u64()),
                            hint.get("wire_type_name").and_then(|w| w.as_str()),
                        ) {
                            *field_counts.entry((fn_num as u32, wt.to_string())).or_insert(0) += 1;
                        }
                    }
                }
            }
        }
        
        let mut fields: Vec<_> = field_counts.iter().collect();
        fields.sort_by(|a, b| b.1.cmp(a.1));
        
        for ((fn_num, wt), count) in fields.iter().take(5) {
            println!("║     #{:2} ({:15}): seen {:>5}x                       ║", fn_num, wt, count);
        }
        println!("║                                                                  ║");
    }
    
    println!("╚════════════════════════════════════════════════════════════════╝");
}

fn main() {
    let cli = Cli::parse();
    
    match cli.command {
        Commands::Stats => cmd_stats(&cli.db),
        Commands::Filter {
            service,
            endpoint,
            exclude_noise,
            high_priority,
            min_size,
            max_size,
            limit,
            output,
        } => cmd_filter(
            &cli.db,
            service,
            endpoint,
            exclude_noise,
            high_priority,
            min_size,
            max_size,
            limit,
            output,
        ),
        Commands::Unique { high_priority, exclude_noise } => {
            cmd_unique(&cli.db, high_priority, exclude_noise);
        }
        Commands::Decode { file, json } => cmd_decode(&file, json),
        Commands::Fields { service, endpoint } => cmd_fields(&cli.db, service, endpoint),
    }
}
