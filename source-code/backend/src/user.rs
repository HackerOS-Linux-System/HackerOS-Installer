use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConfig {
    pub full_name: String,
    pub username: String,
    pub password: String,
    pub hostname: String,
    pub autologin: bool,
    pub root_password: Option<String>,
    pub use_same_password_for_root: bool,
}

impl Default for UserConfig {
    fn default() -> Self {
        Self {
            full_name: String::new(),
            username: String::new(),
            password: String::new(),
            hostname: "hackeros".to_string(),
            autologin: false,
            root_password: None,
            use_same_password_for_root: true,
        }
    }
}
