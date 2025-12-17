//! Scratchpad for AI drafts and ideas

use std::path::PathBuf;
use std::io;

/// AI scratchpad for drafting ideas before implementation
pub struct Scratchpad {
    root: PathBuf,
}

impl Scratchpad {
    pub fn new(root: PathBuf) -> Self {
        std::fs::create_dir_all(&root).ok();
        Self { root }
    }
    
    /// Create a new draft
    pub fn create(&self, name: &str, content: &str) -> io::Result<PathBuf> {
        let filename = sanitize_filename(name);
        let path = self.root.join(format!("{}.md", filename));
        
        // Add header with metadata
        let full_content = format!(
            "# Draft: {}\n\n*Created: {}*\n\n---\n\n{}",
            name,
            chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
            content
        );
        
        std::fs::write(&path, full_content)?;
        Ok(path)
    }
    
    /// Read a draft
    pub fn read(&self, name: &str) -> io::Result<String> {
        let filename = sanitize_filename(name);
        let path = self.root.join(format!("{}.md", filename));
        std::fs::read_to_string(path)
    }
    
    /// Update an existing draft
    pub fn update(&self, name: &str, content: &str) -> io::Result<PathBuf> {
        let filename = sanitize_filename(name);
        let path = self.root.join(format!("{}.md", filename));
        
        // Read existing to preserve header
        let existing = std::fs::read_to_string(&path).ok();
        
        let full_content = if let Some(existing) = existing {
            // Find the content after the header
            if let Some(idx) = existing.find("---\n\n") {
                format!(
                    "{}\n\n*Updated: {}*\n\n{}",
                    &existing[..idx + 5],
                    chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
                    content
                )
            } else {
                content.to_string()
            }
        } else {
            // Create new
            return self.create(name, content);
        };
        
        std::fs::write(&path, full_content)?;
        Ok(path)
    }
    
    /// Append to a draft
    pub fn append(&self, name: &str, content: &str) -> io::Result<PathBuf> {
        let filename = sanitize_filename(name);
        let path = self.root.join(format!("{}.md", filename));
        
        let existing = std::fs::read_to_string(&path).unwrap_or_default();
        let new_content = format!(
            "{}\n\n---\n\n*Added: {}*\n\n{}",
            existing,
            chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
            content
        );
        
        std::fs::write(&path, new_content)?;
        Ok(path)
    }
    
    /// List all drafts
    pub fn list(&self) -> io::Result<Vec<DraftInfo>> {
        let mut drafts = Vec::new();
        
        for entry in std::fs::read_dir(&self.root)? {
            let entry = entry?;
            let path = entry.path();
            
            if path.extension().map_or(false, |e| e == "md") {
                let name = path.file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("unknown")
                    .to_string();
                
                let metadata = entry.metadata()?;
                let modified = metadata.modified()
                    .map(|t| chrono::DateTime::<chrono::Utc>::from(t).to_rfc3339())
                    .unwrap_or_default();
                
                // Read first line for title
                let content = std::fs::read_to_string(&path).unwrap_or_default();
                let title = content.lines().next()
                    .map(|l| l.trim_start_matches("# Draft: ").to_string())
                    .unwrap_or_else(|| name.clone());
                
                drafts.push(DraftInfo {
                    name,
                    title,
                    path,
                    modified,
                    size: metadata.len(),
                });
            }
        }
        
        // Sort by modified time, newest first
        drafts.sort_by(|a, b| b.modified.cmp(&a.modified));
        
        Ok(drafts)
    }
    
    /// Delete a draft
    pub fn delete(&self, name: &str) -> io::Result<()> {
        let filename = sanitize_filename(name);
        let path = self.root.join(format!("{}.md", filename));
        std::fs::remove_file(path)
    }
    
    /// Promote a draft to a real file location
    pub fn promote(&self, name: &str, destination: &PathBuf) -> io::Result<()> {
        let filename = sanitize_filename(name);
        let source = self.root.join(format!("{}.md", filename));
        let content = std::fs::read_to_string(&source)?;
        
        // Remove draft header, keep just content
        let clean_content = if let Some(idx) = content.find("---\n\n") {
            content[idx + 5..].to_string()
        } else {
            content
        };
        
        std::fs::write(destination, clean_content)?;
        
        // Optionally delete the draft
        // std::fs::remove_file(source)?;
        
        Ok(())
    }
}

/// Information about a draft
#[derive(Debug, Clone)]
pub struct DraftInfo {
    pub name: String,
    pub title: String,
    pub path: PathBuf,
    pub modified: String,
    pub size: u64,
}

fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
        .collect::<String>()
        .to_lowercase()
}

