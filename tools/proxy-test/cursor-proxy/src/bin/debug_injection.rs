// ... same content ...
use std::io::Read;
use flate2::read::GzDecoder;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        println!("Usage: debug_injection <file>");
        return;
    }
    
    let path = &args[1];
    println!("Reading {}", path);
    let mut file = std::fs::File::open(path).expect("Failed to open file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).expect("Failed to read file");
    
    // Skip gRPC framing (5 bytes)
    if buffer.len() < 5 {
        println!("Buffer too short");
        return;
    }
    let payload = &buffer[5..];
    
    // Decompress
    let mut decoder = GzDecoder::new(payload);
    let mut decompressed = Vec::new();
    match decoder.read_to_end(&mut decompressed) {
        Ok(_) => println!("Decompressed size: {}", decompressed.len()),
        Err(e) => {
            println!("Gzip failed: {}, assuming uncompressed", e);
            decompressed = payload.to_vec();
        }
    }
    
    match inject_system_message(&decompressed, "TEST INJECTION") {
        Ok(modified) => println!("✅ Modified size: {}", modified.len()),
        Err(e) => println!("❌ Error: {}", e),
    }
}

fn inject_system_message(data: &[u8], system_content: &str) -> Result<Vec<u8>, String> {
    // Parse Level 1: should have Field 1 (StreamUnifiedChatRequest)
    let level1_fields = parse_all_fields(data)?;
    
    let mut new_data = Vec::new();
    let mut injected = false;

    // Create our new system entry
    let system_entry = create_simple_entry(system_content);

    for field in level1_fields {
        // Insert BEFORE the first conversation entry (Field 1)
        if !injected && field.field_num == 1 && field.wire_type == 2 {
            // Write our new entry first
            new_data.push(0x0a); // Field 1 tag (Length Delimited)
            write_varint(&mut new_data, system_entry.len() as u64);
            new_data.extend_from_slice(&system_entry);
            injected = true;
            println!("➕ Inserted new system conversation entry ({} bytes)", system_entry.len());
        }
        
        // Copy the existing field as-is (no modification!)
        new_data.extend_from_slice(&field.raw);
    }
    
    // If no existing conversation entries found, append at end (unlikely for valid request)
    if !injected {
        new_data.push(0x0a);
        write_varint(&mut new_data, system_entry.len() as u64);
        new_data.extend_from_slice(&system_entry);
        println!("➕ Appended new system conversation entry (fallback)");
    }
    
    Ok(new_data)
}

fn create_simple_entry(text: &str) -> Vec<u8> {
    let mut buf = Vec::new();
    
    // Field 1: text (string)
    let final_text = format!("**System Context**\n\n{}", text);
    buf.push(0x0a);
    write_varint(&mut buf, final_text.len() as u64);
    buf.extend_from_slice(final_text.as_bytes());
    
    // Field 2: type (int32) - Use 1 (Human)
    buf.push(0x10);
    write_varint(&mut buf, 1);
    
    // Field 13: bubble_id (string)
    let uuid = "test-uuid-1234-5678";
    buf.push(0x6a); // 13 << 3 | 2
    write_varint(&mut buf, uuid.len() as u64);
    buf.extend_from_slice(uuid.as_bytes());
    
    // Field 29: unknown (int32) - Value 1
    buf.push(0xe8); 
    buf.push(0x01); 
    write_varint(&mut buf, 1);

    buf
}

#[derive(Clone)]
struct ProtobufField {
    field_num: u64,
    wire_type: u8,
    raw: Vec<u8>, 
}

fn parse_all_fields(data: &[u8]) -> Result<Vec<ProtobufField>, String> {
    let mut fields = Vec::new();
    let mut pos = 0;
    
    while pos < data.len() {
        let start = pos;
        
        let (tag, tag_len) = match read_varint(&data[pos..]) {
            Some(v) => v,
            None => return Err(format!("Failed to read tag at pos {}", pos)),
        };
        pos += tag_len;
        
        let field_num = tag >> 3;
        let wire_type = (tag & 0x7) as u8;
        
        let field_end = match wire_type {
            0 => { // Varint
                let (_, val_len) = match read_varint(&data[pos..]) {
                    Some(v) => v,
                    None => return Err("Failed to read varint".to_string()),
                };
                pos + val_len
            }
            1 => { // 64-bit
                if pos + 8 > data.len() { return Err("Overflow".to_string()); }
                pos + 8
            }
            2 => { // LEN
                let (len, len_bytes) = match read_varint(&data[pos..]) {
                    Some(v) => v,
                    None => return Err("Failed to read length".to_string()),
                };
                let len = len as usize;
                let end = pos + len_bytes + len;
                if end > data.len() { return Err(format!("Field {} length {} overflow", field_num, len)); }
                end
            }
            5 => { // 32-bit
                if pos + 4 > data.len() { return Err("Overflow".to_string()); }
                pos + 4
            }
            _ => return Err(format!("Unknown wire type {} at pos {}", wire_type, pos)),
        };
        
        fields.push(ProtobufField {
            field_num,
            wire_type,
            raw: data[start..field_end].to_vec(),
        });
        
        pos = field_end;
    }
    
    Ok(fields)
}

fn write_varint(buf: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            buf.push(byte);
            break;
        } else {
            buf.push(byte | 0x80);
        }
    }
}

fn read_varint(buf: &[u8]) -> Option<(u64, usize)> {
    if buf.is_empty() { return None; }
    let mut value = 0u64;
    let mut shift = 0;
    
    for (i, &byte) in buf.iter().enumerate() {
        value |= ((byte & 0x7f) as u64) << shift;
        if byte & 0x80 == 0 {
            return Some((value, i + 1));
        }
        shift += 7;
        if shift >= 64 {
            return None;
        }
    }
    None
}
