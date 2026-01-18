pub mod auth;
pub mod client;

pub mod aiserver {
    pub mod v1 {
        include!(concat!(env!("OUT_DIR"), "/aiserver.v1.rs"));
    }
}
