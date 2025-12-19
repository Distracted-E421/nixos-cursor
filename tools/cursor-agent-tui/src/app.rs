//! Application state for cursor-agent-tui

use crate::api::{ChatEvent, CursorClient};
use crate::config::Config;
use crate::context::ContextManager;
use crate::error::Result;
use crate::state::{MessageRole, StateManager};
use crate::tools::ToolRunner;
use futures::StreamExt;
use tracing::{debug, info};

/// Application mode
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mode {
    /// Normal navigation mode
    Normal,
    /// Typing input
    Insert,
    /// Command mode (: prefix)
    Command,
    /// Selecting files for context
    FileSelect,
    /// Viewing diff preview
    DiffPreview,
}

/// Application state
pub struct App {
    /// API client
    client: CursorClient,
    /// Context manager
    context: ContextManager,
    /// Tool runner
    tools: ToolRunner,
    /// State manager
    state: StateManager,
    /// Configuration
    config: Config,
    /// Current mode
    mode: Mode,
    /// Input buffer
    input: String,
    /// Command buffer (for : commands)
    command: String,
    /// Scroll offset for conversation view
    scroll_offset: usize,
    /// Whether currently streaming a response
    streaming: bool,
    /// Pending response text (accumulated during streaming)
    pending_response: String,
    /// Status message
    status: Option<String>,
    /// Should quit
    should_quit: bool,
}

impl App {
    /// Create a new application
    pub fn new(
        client: CursorClient,
        context: ContextManager,
        tools: ToolRunner,
        state: StateManager,
        config: Config,
    ) -> Result<Self> {
        Ok(Self {
            client,
            context,
            tools,
            state,
            config,
            mode: Mode::Normal,
            input: String::new(),
            command: String::new(),
            scroll_offset: 0,
            streaming: false,
            pending_response: String::new(),
            status: None,
            should_quit: false,
        })
    }

    /// Get current mode
    pub fn mode(&self) -> Mode {
        self.mode
    }

    /// Set mode
    pub fn set_mode(&mut self, mode: Mode) {
        self.mode = mode;
    }

    /// Get input buffer
    pub fn input(&self) -> &str {
        &self.input
    }

    /// Get input buffer mutably
    pub fn input_mut(&mut self) -> &mut String {
        &mut self.input
    }

    /// Get command buffer
    pub fn command(&self) -> &str {
        &self.command
    }

    /// Get command buffer mutably
    pub fn command_mut(&mut self) -> &mut String {
        &mut self.command
    }

    /// Get context manager
    pub fn context(&self) -> &ContextManager {
        &self.context
    }

    /// Get context manager mutably
    pub fn context_mut(&mut self) -> &mut ContextManager {
        &mut self.context
    }

    /// Get state manager
    pub fn state(&self) -> &StateManager {
        &self.state
    }

    /// Get state manager mutably
    pub fn state_mut(&mut self) -> &mut StateManager {
        &mut self.state
    }

    /// Get scroll offset
    pub fn scroll_offset(&self) -> usize {
        self.scroll_offset
    }

    /// Set scroll offset
    pub fn set_scroll_offset(&mut self, offset: usize) {
        self.scroll_offset = offset;
    }

    /// Is streaming
    pub fn is_streaming(&self) -> bool {
        self.streaming
    }

    /// Get status message
    pub fn status(&self) -> Option<&str> {
        self.status.as_deref()
    }

    /// Set status message
    pub fn set_status(&mut self, status: Option<String>) {
        self.status = status;
    }

    /// Should quit
    pub fn should_quit(&self) -> bool {
        self.should_quit
    }

    /// Request quit
    pub fn quit(&mut self) {
        self.should_quit = true;
    }

    /// Get pending response
    pub fn pending_response(&self) -> &str {
        &self.pending_response
    }

    /// Submit the current input
    pub async fn submit(&mut self) -> Result<()> {
        if self.input.trim().is_empty() {
            return Ok(());
        }

        let query = std::mem::take(&mut self.input);
        info!("Submitting query: {}", query);

        // Ensure we have a conversation
        if self.state.current().is_none() {
            self.state.new_conversation(&self.config.api.default_model);
        }

        // Add user message
        if let Some(conv) = self.state.current_mut() {
            conv.add_message(MessageRole::User, query.clone());
        }

        // Build context
        let ctx = self.context.build_context(&query);

        // Start streaming
        self.streaming = true;
        self.pending_response.clear();
        self.status = Some("Streaming...".to_string());

        // Stream response
        let mut stream = self.client.stream_chat(&query, ctx).await?;

        while let Some(event) = stream.next().await {
            match event? {
                ChatEvent::Text(text) => {
                    self.pending_response.push_str(&text);
                }
                ChatEvent::ToolCall { name, args } => {
                    self.status = Some(format!("Running tool: {}", name));
                    
                    // Execute tool
                    let result = self.tools.execute(&name, &args).await;
                    let (result_str, success) = match result {
                        Ok(r) => (r, true),
                        Err(e) => (e.to_string(), false),
                    };

                    // Record tool call
                    if let Some(conv) = self.state.current_mut() {
                        conv.add_tool_call(name.clone(), args.clone(), Some(result_str.clone()), success);
                    }

                    debug!("Tool {} result: {} bytes", name, result_str.len());
                }
                ChatEvent::Done { usage } => {
                    self.status = Some(format!(
                        "Done ({} tokens)",
                        usage.prompt_tokens + usage.completion_tokens
                    ));
                }
                ChatEvent::Thinking => {
                    self.status = Some("Thinking...".to_string());
                }
                ChatEvent::Error(msg) => {
                    self.status = Some(format!("Error: {}", msg));
                }
                _ => {}
            }
        }

        // Finalize response
        if !self.pending_response.is_empty() {
            let response = std::mem::take(&mut self.pending_response);
            if let Some(conv) = self.state.current_mut() {
                conv.add_message(MessageRole::Assistant, response);
                conv.generate_title();
            }
        }

        self.streaming = false;
        self.state.save_current()?;

        Ok(())
    }

    /// Execute a command
    pub fn execute_command(&mut self) -> Result<()> {
        let cmd = std::mem::take(&mut self.command);
        let parts: Vec<&str> = cmd.trim().split_whitespace().collect();

        if parts.is_empty() {
            return Ok(());
        }

        match parts[0] {
            "q" | "quit" | "exit" => {
                self.quit();
            }
            "w" | "write" | "save" => {
                self.state.save_current()?;
                self.status = Some("Saved".to_string());
            }
            "new" => {
                self.state.new_conversation(&self.config.api.default_model);
                self.status = Some("New conversation".to_string());
            }
            "add" | "file" => {
                if parts.len() > 1 {
                    let path = std::path::Path::new(parts[1]);
                    match self.context.add_file(path) {
                        Ok(_) => self.status = Some(format!("Added: {}", parts[1])),
                        Err(e) => self.status = Some(format!("Error: {}", e)),
                    }
                }
            }
            "remove" | "rm" => {
                if parts.len() > 1 {
                    let path = std::path::Path::new(parts[1]);
                    self.context.remove_file(path);
                    self.status = Some(format!("Removed: {}", parts[1]));
                }
            }
            "clear" => {
                self.context.clear();
                self.status = Some("Context cleared".to_string());
            }
            "files" => {
                let files = self.context.list_files();
                self.status = Some(format!("Files: {}", files.join(", ")));
            }
            "history" => {
                let count = self.state.history().count();
                self.status = Some(format!("{} conversations in history", count));
            }
            "stats" => {
                let stats = self.state.stats();
                self.status = Some(format!(
                    "{} convos, {} bytes / {} max",
                    stats.conversation_count,
                    stats.total_size,
                    stats.max_size
                ));
            }
            _ => {
                self.status = Some(format!("Unknown command: {}", parts[0]));
            }
        }

        self.mode = Mode::Normal;
        Ok(())
    }
}

