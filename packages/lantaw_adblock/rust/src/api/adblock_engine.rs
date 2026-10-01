use std::sync::Mutex;

use adblock::{request::Request, Engine};

/// Thin wrapper around Brave's `adblock` (adblock-rust) matching engine.
///
/// Exposed to Dart as an opaque handle: construct it once per filter list
/// with `AdblockEngine.fromListText`, then reuse it for every request the
/// embedded player's WebView makes.
pub struct AdblockEngine {
    engine: Mutex<Engine>,
}

impl AdblockEngine {
    /// `list_text` is filter-list source in Adblock Plus / uBlock Origin
    /// syntax (the same format as EasyList), newline separated.
    #[flutter_rust_bridge::frb(sync)]
    pub fn from_list_text(list_text: String) -> AdblockEngine {
        AdblockEngine {
            engine: Mutex::new(Engine::new_with_list_text(list_text)),
        }
    }

    /// Whether a network request should be blocked.
    ///
    /// `request_type` follows the standard Adblock Plus resource-type
    /// vocabulary: "document", "sub_frame", "script", "image",
    /// "stylesheet", "xmlhttprequest", "font", "media", "websocket",
    /// "other", etc.
    #[flutter_rust_bridge::frb(sync)]
    pub fn should_block(&self, url: String, source_url: String, request_type: String) -> bool {
        let Ok(request) = Request::new(&url, &source_url, &request_type, "GET") else {
            return false;
        };
        let engine = self.engine.lock().unwrap();
        engine.check_network_request(&request).should_block()
    }

    /// CSS selectors for elements that cosmetic filter rules say should be
    /// hidden on this page (`{ display: none !important; }`).
    #[flutter_rust_bridge::frb(sync)]
    pub fn cosmetic_hide_selectors(&self, url: String) -> Vec<String> {
        let engine = self.engine.lock().unwrap();
        engine
            .url_cosmetic_resources(&url)
            .hide_selectors
            .into_iter()
            .collect()
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
