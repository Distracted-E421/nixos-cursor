//! Cursor Dialog Daemon Library
//!
//! Provides D-Bus IPC for AI agent interactive dialogs.

pub mod dbus_interface;
pub mod dialog;
pub mod gui;

pub use dialog::{DialogManager, DialogRequest, DialogResponse, DialogType};
pub use dbus_interface::{ChoiceOption, DialogInterface, FileFilter, FilePickerMode};

