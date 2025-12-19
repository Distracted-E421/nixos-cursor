//! API client tests
//! 
//! These tests require a valid Cursor auth token to run.
//! They're integration tests that hit the actual Cursor API.

use std::path::PathBuf;

/// Helper to get auth token from Cursor database
fn get_auth_token() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let db_path = PathBuf::from(&home)
        .join(".config/Cursor/User/globalStorage/state.vscdb");
    
    if !db_path.exists() {
        return None;
    }
    
    let conn = rusqlite::Connection::open_with_flags(
        &db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).ok()?;
    
    conn.query_row(
        "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'",
        [],
        |row| row.get(0),
    ).ok()
}

/// Test available models endpoint
#[tokio::test]
async fn test_available_models() {
    let Some(token) = get_auth_token() else {
        println!("⚠ Skipping API test - no auth token");
        return;
    };
    
    let client = reqwest::Client::new();
    let response = client
        .post("https://api2.cursor.sh/aiserver.v1.AiService/AvailableModels")
        .header("Authorization", format!("Bearer {}", token))
        .header("Content-Type", "application/json")
        .header("Connect-Protocol-Version", "1")
        .body("{}")
        .send()
        .await
        .expect("Failed to send request");
    
    assert!(response.status().is_success(), "API request failed: {}", response.status());
    
    let body: serde_json::Value = response.json().await.expect("Failed to parse JSON");
    
    let models = body["models"].as_array().expect("Expected models array");
    assert!(!models.is_empty(), "Expected at least one model");
    
    println!("✓ Found {} models", models.len());
    
    // Check for expected models
    let model_names: Vec<&str> = models.iter()
        .filter_map(|m| m["name"].as_str())
        .collect();
    
    let expected = ["claude-4.5-sonnet", "gpt-4.1"];
    for name in expected {
        if model_names.contains(&name) {
            println!("✓ Found expected model: {}", name);
        } else {
            // Models may change, so just log
            println!("⚠ Expected model not found: {}", name);
        }
    }
}

/// Test check queue position endpoint
#[tokio::test]
async fn test_check_queue_position() {
    let Some(token) = get_auth_token() else {
        println!("⚠ Skipping API test - no auth token");
        return;
    };
    
    let client = reqwest::Client::new();
    let request_id = uuid::Uuid::new_v4().to_string();
    
    let body = serde_json::json!({
        "request_id": request_id,
        "model": {
            "model_name": "claude-4.5-sonnet"
        }
    });
    
    let response = client
        .post("https://api2.cursor.sh/aiserver.v1.AiService/CheckQueuePosition")
        .header("Authorization", format!("Bearer {}", token))
        .header("Content-Type", "application/json")
        .header("Connect-Protocol-Version", "1")
        .json(&body)
        .send()
        .await
        .expect("Failed to send request");
    
    // This might fail if there's no queue, which is fine
    println!("Queue position response: {} - {:?}", 
             response.status(), 
             response.text().await.unwrap_or_default());
}

/// Test model info structure
#[tokio::test]
async fn test_model_info_structure() {
    let Some(token) = get_auth_token() else {
        println!("⚠ Skipping API test - no auth token");
        return;
    };
    
    let client = reqwest::Client::new();
    let response = client
        .post("https://api2.cursor.sh/aiserver.v1.AiService/AvailableModels")
        .header("Authorization", format!("Bearer {}", token))
        .header("Content-Type", "application/json")
        .header("Connect-Protocol-Version", "1")
        .body("{}")
        .send()
        .await
        .expect("Failed to send request");
    
    let body: serde_json::Value = response.json().await.expect("Failed to parse JSON");
    let models = body["models"].as_array().expect("Expected models array");
    
    // Check first model has expected fields
    let first = &models[0];
    assert!(first.get("name").is_some(), "Model should have name");
    assert!(first.get("supportsAgent").is_some(), "Model should have supportsAgent");
    assert!(first.get("supportsThinking").is_some(), "Model should have supportsThinking");
    
    println!("✓ Model structure validated");
    println!("  First model: {}", first["name"]);
    println!("  Supports agent: {}", first["supportsAgent"]);
    println!("  Supports thinking: {}", first["supportsThinking"]);
}

