use std::io::Result;

fn main() -> Result<()> {
    // Tell Cargo to rerun if proto files change
    println!("cargo:rerun-if-changed=proto/aiserver.proto");
    
    // Configure prost-build
    let mut config = prost_build::Config::new();
    
    // Generate code in OUT_DIR
    config.out_dir("src/generated");
    
    // Create the output directory if it doesn't exist
    std::fs::create_dir_all("src/generated")?;
    
    // prost::Message already derives Clone and PartialEq, so don't add them again
    // Only add extra derives if needed (like Default for easier construction)
    // config.type_attribute(".", "#[derive(Default)]");
    
    // Compile the proto file
    config.compile_protos(&["proto/aiserver.proto"], &["proto/"])?;
    
    Ok(())
}

