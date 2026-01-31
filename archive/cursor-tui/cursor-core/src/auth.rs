use anyhow::{Result, Context};
use sqlite::State;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct CursorAuth {
    pub access_token: String,
    pub refresh_token: String,
}

pub fn get_auth_db_path() -> PathBuf {
    let home = dirs::home_dir().expect("Could not find home directory");
    home.join(".config/Cursor/User/globalStorage/state.vscdb")
}

pub fn extract_auth_from_db(db_path: &PathBuf) -> Result<CursorAuth> {
    let connection = sqlite::open(db_path).context("Failed to open state.vscdb")?;

    let query = "SELECT value FROM ItemTable WHERE key = ?";
    let mut statement = connection.prepare(query)?;

    let access_token = {
        statement.bind((1, "cursorAuth/accessToken"))?;
        if let State::Row = statement.next()? {
            statement.read::<String, _>(0)?
        } else {
            return Err(anyhow::anyhow!("cursorAuth/accessToken not found"));
        }
    };
    
    statement.reset()?;

    let refresh_token = {
        statement.bind((1, "cursorAuth/refreshToken"))?;
        if let State::Row = statement.next()? {
            statement.read::<String, _>(0)?
        } else {
            return Err(anyhow::anyhow!("cursorAuth/refreshToken not found"));
        }
    };

    Ok(CursorAuth {
        access_token,
        refresh_token,
    })
}
