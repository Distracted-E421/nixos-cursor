//! Authentication tests

use std::path::PathBuf;

/// Test that we can find the Cursor database
#[test]
fn test_find_cursor_db() {
    let home = std::env::var("HOME").expect("HOME not set");
    let db_path = PathBuf::from(&home)
        .join(".config/Cursor/User/globalStorage/state.vscdb");
    
    // Database should exist if Cursor is installed
    if db_path.exists() {
        assert!(db_path.is_file(), "state.vscdb should be a file");
        
        // Check file size is reasonable
        let metadata = std::fs::metadata(&db_path).expect("Failed to read metadata");
        assert!(metadata.len() > 0, "Database should not be empty");
        
        println!("✓ Found Cursor database at: {:?}", db_path);
        println!("  Size: {} bytes", metadata.len());
    } else {
        println!("⚠ Cursor database not found (Cursor not installed?)");
    }
}

/// Test token extraction from database
#[test]
fn test_extract_token() {
    let home = std::env::var("HOME").expect("HOME not set");
    let db_path = PathBuf::from(&home)
        .join(".config/Cursor/User/globalStorage/state.vscdb");
    
    if !db_path.exists() {
        println!("⚠ Skipping token test - Cursor not installed");
        return;
    }
    
    // Open database read-only
    let conn = rusqlite::Connection::open_with_flags(
        &db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).expect("Failed to open database");
    
    // Try to find the access token
    let result: Result<String, _> = conn.query_row(
        "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'",
        [],
        |row| row.get(0),
    );
    
    match result {
        Ok(token) => {
            assert!(token.starts_with("eyJ"), "Token should be a JWT");
            println!("✓ Found auth token: {}...{}", &token[..20], &token[token.len()-10..]);
        }
        Err(_) => {
            println!("⚠ No auth token found (not logged in?)");
        }
    }
}

/// Test ItemTable structure
#[test]
fn test_itemtable_structure() {
    let home = std::env::var("HOME").expect("HOME not set");
    let db_path = PathBuf::from(&home)
        .join(".config/Cursor/User/globalStorage/state.vscdb");
    
    if !db_path.exists() {
        println!("⚠ Skipping test - Cursor not installed");
        return;
    }
    
    let conn = rusqlite::Connection::open_with_flags(
        &db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).expect("Failed to open database");
    
    // List cursorAuth keys
    let mut stmt = conn.prepare(
        "SELECT key FROM ItemTable WHERE key LIKE 'cursorAuth%'"
    ).expect("Failed to prepare statement");
    
    let keys: Vec<String> = stmt.query_map([], |row| row.get(0))
        .expect("Failed to query")
        .filter_map(|r| r.ok())
        .collect();
    
    println!("cursorAuth keys in ItemTable:");
    for key in &keys {
        println!("  - {}", key);
    }
    
    // Verify expected keys exist
    let expected = ["cursorAuth/accessToken", "cursorAuth/refreshToken", "cursorAuth/cachedEmail"];
    for key in expected {
        if keys.iter().any(|k| k == key) {
            println!("✓ Found expected key: {}", key);
        } else {
            println!("⚠ Missing expected key: {}", key);
        }
    }
}

