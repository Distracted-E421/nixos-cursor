//! Terminal user interface for cursor-agent-tui

use crate::app::{App, Mode};
use anyhow::Result;
use crate::state::MessageRole;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame, Terminal,
};
use std::io;
use tracing::info;

/// Run the TUI
pub async fn run(mut app: App, initial_message: Option<String>) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Initialize conversation if none exists
    if app.state().current().is_none() {
        app.state_mut().new_conversation("claude-3-5-sonnet-20241022");
    }

    // Handle initial message
    if let Some(msg) = initial_message {
        app.input_mut().push_str(&msg);
        app.submit().await.ok();
    }

    // Main loop
    let result = run_loop(&mut terminal, &mut app).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

/// Main event loop
async fn run_loop<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    app: &mut App,
) -> Result<()> {
    loop {
        // Draw UI
        terminal.draw(|f| draw(f, app))?;

        // Handle events with timeout for async updates
        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                match app.mode() {
                    Mode::Normal => handle_normal_mode(app, key).await?,
                    Mode::Insert => handle_insert_mode(app, key).await?,
                    Mode::Command => handle_command_mode(app, key)?,
                    Mode::FileSelect => handle_file_select_mode(app, key)?,
                    Mode::DiffPreview => handle_diff_preview_mode(app, key)?,
                }
            }
        }

        if app.should_quit() {
            break;
        }
    }

    Ok(())
}

/// Draw the UI
fn draw(f: &mut Frame, app: &App) {
    let size = f.size();

    // Main layout: header, content, input, status
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),  // Header
            Constraint::Min(5),     // Content
            Constraint::Length(3),  // Input
            Constraint::Length(1),  // Status
        ])
        .split(size);

    // Header
    draw_header(f, app, chunks[0]);

    // Content area: files panel + conversation
    let content_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(20),  // Files
            Constraint::Percentage(80),  // Conversation
        ])
        .split(chunks[1]);

    draw_files_panel(f, app, content_chunks[0]);
    draw_conversation(f, app, content_chunks[1]);

    // Input area
    draw_input(f, app, chunks[2]);

    // Status bar
    draw_status(f, app, chunks[3]);
}

fn draw_header(f: &mut Frame, app: &App, area: Rect) {
    let cwd = app.context().cwd().display().to_string();
    let model = app.state()
        .current()
        .map(|c| c.model.as_str())
        .unwrap_or("--");

    let header = Line::from(vec![
        Span::styled(" cursor-agent ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::raw("│ "),
        Span::styled(&cwd, Style::default().fg(Color::White)),
        Span::raw(" │ Model: "),
        Span::styled(model, Style::default().fg(Color::Yellow)),
    ]);

    f.render_widget(Paragraph::new(header), area);
}

fn draw_files_panel(f: &mut Frame, app: &App, area: Rect) {
    let files: Vec<ListItem> = app.context()
        .list_files()
        .iter()
        .map(|f| {
            ListItem::new(Line::from(vec![
                Span::styled("📄 ", Style::default()),
                Span::raw(*f),
            ]))
        })
        .collect();

    let files_block = Block::default()
        .title(" Context Files ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));

    let list = List::new(files)
        .block(files_block)
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED));

    f.render_widget(list, area);
}

fn draw_conversation(f: &mut Frame, app: &App, area: Rect) {
    let mut lines: Vec<Line> = Vec::new();

    if let Some(conv) = app.state().current() {
        for msg in &conv.messages {
            let (prefix, style) = match msg.role {
                MessageRole::User => ("You: ", Style::default().fg(Color::Cyan)),
                MessageRole::Assistant => ("Agent: ", Style::default().fg(Color::Green)),
                MessageRole::System => ("System: ", Style::default().fg(Color::Yellow)),
                MessageRole::Tool => ("Tool: ", Style::default().fg(Color::Magenta)),
            };

            lines.push(Line::from(vec![
                Span::styled(prefix, style.add_modifier(Modifier::BOLD)),
            ]));

            // Wrap message content
            for line in msg.content.lines() {
                lines.push(Line::from(Span::raw(format!("  {}", line))));
            }

            // Show tool calls
            for tool_call in &msg.tool_calls {
                let status = if tool_call.success { "✓" } else { "✗" };
                lines.push(Line::from(vec![
                    Span::styled(
                        format!("  [{}] {}", status, tool_call.name),
                        Style::default().fg(Color::Magenta),
                    ),
                ]));
            }

            lines.push(Line::from(""));
        }
    }

    // Add pending response if streaming
    if app.is_streaming() && !app.pending_response().is_empty() {
        lines.push(Line::from(vec![
            Span::styled("Agent: ", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)),
        ]));
        for line in app.pending_response().lines() {
            lines.push(Line::from(Span::raw(format!("  {}", line))));
        }
        lines.push(Line::from(Span::styled("▌", Style::default().fg(Color::Green))));
    }

    let conversation = Paragraph::new(lines)
        .block(
            Block::default()
                .title(" Conversation ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        )
        .wrap(Wrap { trim: false })
        .scroll((app.scroll_offset() as u16, 0));

    f.render_widget(conversation, area);
}

fn draw_input(f: &mut Frame, app: &App, area: Rect) {
    let (content, title) = match app.mode() {
        Mode::Command => (format!(":{}", app.command()), " Command "),
        _ => (app.input().to_string(), " Input "),
    };

    let style = match app.mode() {
        Mode::Insert => Style::default().fg(Color::Yellow),
        Mode::Command => Style::default().fg(Color::Cyan),
        _ => Style::default().fg(Color::White),
    };

    let input = Paragraph::new(content)
        .block(
            Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_style(style),
        );

    f.render_widget(input, area);

    // Show cursor in insert/command mode
    if matches!(app.mode(), Mode::Insert | Mode::Command) {
        let cursor_pos = match app.mode() {
            Mode::Command => app.command().len() + 1, // +1 for :
            _ => app.input().len(),
        };
        f.set_cursor(area.x + 1 + cursor_pos as u16, area.y + 1);
    }
}

fn draw_status(f: &mut Frame, app: &App, area: Rect) {
    let mode_str = match app.mode() {
        Mode::Normal => "NORMAL",
        Mode::Insert => "INSERT",
        Mode::Command => "COMMAND",
        Mode::FileSelect => "FILES",
        Mode::DiffPreview => "DIFF",
    };

    let mode_style = match app.mode() {
        Mode::Insert => Style::default().fg(Color::Black).bg(Color::Yellow),
        Mode::Command => Style::default().fg(Color::Black).bg(Color::Cyan),
        _ => Style::default().fg(Color::Black).bg(Color::Blue),
    };

    let status_msg = app.status().unwrap_or("");

    let status = Line::from(vec![
        Span::styled(format!(" {} ", mode_str), mode_style),
        Span::raw(" "),
        Span::styled(status_msg, Style::default().fg(Color::White)),
        Span::raw(" │ "),
        Span::styled(
            "[i]nsert [:]command [f]iles [q]uit",
            Style::default().fg(Color::DarkGray),
        ),
    ]);

    f.render_widget(Paragraph::new(status), area);
}

async fn handle_normal_mode(app: &mut App, key: event::KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Char('q') => app.quit(),
        KeyCode::Char('i') => app.set_mode(Mode::Insert),
        KeyCode::Char(':') => app.set_mode(Mode::Command),
        KeyCode::Char('f') => app.set_mode(Mode::FileSelect),
        KeyCode::Char('j') | KeyCode::Down => {
            app.set_scroll_offset(app.scroll_offset().saturating_add(1));
        }
        KeyCode::Char('k') | KeyCode::Up => {
            app.set_scroll_offset(app.scroll_offset().saturating_sub(1));
        }
        KeyCode::Char('G') => {
            // Scroll to bottom
            app.set_scroll_offset(usize::MAX);
        }
        KeyCode::Char('g') => {
            if key.modifiers.contains(KeyModifiers::NONE) {
                // gg - scroll to top
                app.set_scroll_offset(0);
            }
        }
        _ => {}
    }
    Ok(())
}

async fn handle_insert_mode(app: &mut App, key: event::KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc => app.set_mode(Mode::Normal),
        KeyCode::Enter => {
            if key.modifiers.contains(KeyModifiers::SHIFT) {
                // Shift+Enter: newline
                app.input_mut().push('\n');
            } else {
                // Enter: submit
                app.submit().await?;
            }
        }
        KeyCode::Char(c) => {
            app.input_mut().push(c);
        }
        KeyCode::Backspace => {
            app.input_mut().pop();
        }
        _ => {}
    }
    Ok(())
}

fn handle_command_mode(app: &mut App, key: event::KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc => {
            app.command_mut().clear();
            app.set_mode(Mode::Normal);
        }
        KeyCode::Enter => {
            app.execute_command()?;
        }
        KeyCode::Char(c) => {
            app.command_mut().push(c);
        }
        KeyCode::Backspace => {
            if app.command().is_empty() {
                app.set_mode(Mode::Normal);
            } else {
                app.command_mut().pop();
            }
        }
        _ => {}
    }
    Ok(())
}

fn handle_file_select_mode(app: &mut App, key: event::KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('q') => app.set_mode(Mode::Normal),
        // TODO: file selection logic
        _ => {}
    }
    Ok(())
}

fn handle_diff_preview_mode(app: &mut App, key: event::KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('q') => app.set_mode(Mode::Normal),
        // TODO: diff navigation
        _ => {}
    }
    Ok(())
}

