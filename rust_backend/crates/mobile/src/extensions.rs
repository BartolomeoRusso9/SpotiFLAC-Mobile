use crate::cancellation::RequestLease;
use spotiflac_extensions::environment::{
    EnvironmentError, ExtensionEnvironment as CoreEnvironment,
};
use spotiflac_extensions::{ExtensionError, ExtensionRuntime, RuntimeLimits};
use std::path::Path;
use std::sync::{Arc, Mutex};

/// Keeps operation directories accessible until native finalization finishes.
/// Explicit close and object destruction both release only these grants.
#[derive(uniffi::Object)]
pub struct DownloadDirectoryScope {
    grants: Mutex<Option<Vec<spotiflac_extensions::files::TemporaryGrant>>>,
}

#[uniffi::export]
impl DownloadDirectoryScope {
    pub fn release(&self) {
        self.grants
            .lock()
            .expect("download directory scope lock")
            .take();
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum JsExtensionError {
    #[error("extension runtime closed")]
    Closed,
    #[error("extension runtime busy")]
    Busy,
    #[error("execution timeout exceeded")]
    Timeout,
    #[error("{0}")]
    Cancelled(String),
    #[error("extension did not call registerExtension()")]
    NotRegistered,
    #[error("extension function not found: {0}")]
    MissingFunction(String),
    #[error("invalid extension input: {0}")]
    InvalidInput(String),
    #[error("{0}")]
    Script(String),
    #[error("extension environment closed")]
    EnvironmentClosed,
    #[error("{0}")]
    Storage(String),
    #[error("{0}")]
    Manifest(String),
    #[error("{0}")]
    Gate(String),
    #[error("{0}")]
    Network(String),
    #[error("{0}")]
    Auth(String),
    #[error("{0}")]
    Index(String),
}

impl From<EnvironmentError> for JsExtensionError {
    fn from(error: EnvironmentError) -> Self {
        match error {
            EnvironmentError::Closed => Self::EnvironmentClosed,
            EnvironmentError::Runtime(error) => error.into(),
            EnvironmentError::Storage(error) => Self::Storage(error.to_string()),
            EnvironmentError::Manifest(error) => Self::Manifest(error.to_string()),
            EnvironmentError::Gate(message) => Self::Gate(message),
            EnvironmentError::Network(error) => Self::Network(error.to_string()),
            EnvironmentError::Auth(error) => Self::Auth(error),
            EnvironmentError::Index(error) => Self::Index(error),
        }
    }
}

impl From<ExtensionError> for JsExtensionError {
    fn from(error: ExtensionError) -> Self {
        match error {
            ExtensionError::Closed => Self::Closed,
            ExtensionError::Busy => Self::Busy,
            ExtensionError::Timeout => Self::Timeout,
            ExtensionError::Cancelled(error) => Self::Cancelled(error.to_string()),
            ExtensionError::NotRegistered => Self::NotRegistered,
            ExtensionError::MissingFunction(method) => Self::MissingFunction(method),
            ExtensionError::InvalidInput(message) => Self::InvalidInput(message),
            ExtensionError::Script(message) => Self::Script(message),
        }
    }
}

/// Migration runtime. Calls must run off the UI thread. The complete extension
/// manager and network/file/auth hosts are not yet wired into the mobile app.
#[derive(uniffi::Object)]
pub struct JsExtension {
    inner: Arc<ExtensionRuntime>,
}

#[uniffi::export]
impl JsExtension {
    pub fn download_state(&self) -> Arc<crate::progress::DownloadState> {
        Arc::new(crate::progress::DownloadState {
            inner: self.inner.download_state(),
        })
    }

    #[uniffi::constructor]
    pub fn new(
        source: String,
        settings_json: String,
        timeout_ms: u64,
    ) -> Result<Self, JsExtensionError> {
        let limits = RuntimeLimits {
            timeout_ms: if timeout_ms == 0 { 30_000 } else { timeout_ms },
            ..RuntimeLimits::default()
        };
        Ok(Self {
            inner: Arc::new(ExtensionRuntime::load(&source, &settings_json, limits)?),
        })
    }

    pub fn call(
        &self,
        method: String,
        arguments_json: String,
        lease: Option<Arc<RequestLease>>,
        timeout_ms: u64,
    ) -> Result<String, JsExtensionError> {
        let lease = lease.map(|lease| Arc::clone(&lease.inner));
        self.inner
            .call(&method, &arguments_json, lease, timeout_ms)
            .map_err(Into::into)
    }

    pub fn preflight_signed_session(
        &self,
        lease: Option<Arc<RequestLease>>,
        timeout_ms: u64,
    ) -> Result<bool, JsExtensionError> {
        self.inner
            .preflight_signed_session(lease.map(|lease| Arc::clone(&lease.inner)), timeout_ms)
            .map_err(Into::into)
    }

    pub fn call_download(
        &self,
        method: String,
        arguments_json: String,
        lease: Option<Arc<RequestLease>>,
        resolution_timeout_ms: u64,
    ) -> Result<String, JsExtensionError> {
        self.inner
            .call_download(
                &method,
                &arguments_json,
                lease.map(|lease| Arc::clone(&lease.inner)),
                resolution_timeout_ms,
            )
            .map_err(Into::into)
    }

    pub fn take_verification_url(&self) -> String {
        self.inner.take_verification_url()
    }

    pub fn call_download_for_item(
        &self,
        method: String,
        arguments_json: String,
        item_id: String,
        resolution_timeout_ms: u64,
    ) -> Result<String, JsExtensionError> {
        self.inner
            .call_download_for_item(&method, &arguments_json, &item_id, resolution_timeout_ms)
            .map_err(Into::into)
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }
}

#[derive(uniffi::Object)]
pub struct ExtensionEnvironment {
    pub(crate) inner: Arc<CoreEnvironment>,
}

#[uniffi::export]
impl ExtensionEnvironment {
    pub fn log_buffer(&self) -> Arc<crate::logging::LogBuffer> {
        Arc::new(crate::logging::LogBuffer {
            inner: self.inner.log_buffer(),
        })
    }

    pub fn ffmpeg_commands(&self) -> Arc<crate::ffmpeg::FfmpegCommands> {
        Arc::new(crate::ffmpeg::FfmpegCommands {
            inner: self.inner.ffmpeg_commands(),
        })
    }

    pub fn download_state(&self) -> Arc<crate::progress::DownloadState> {
        Arc::new(crate::progress::DownloadState {
            inner: self.inner.download_state(),
        })
    }

    #[uniffi::constructor]
    pub fn new(
        data_directory: String,
        master_key: String,
        app_version: String,
    ) -> Result<Self, JsExtensionError> {
        let master_key = zeroize::Zeroizing::new(master_key);
        Ok(Self {
            inner: Arc::new(CoreEnvironment::new(
                Path::new(&data_directory),
                &master_key,
                &app_version,
            )?),
        })
    }

    pub fn load(
        &self,
        manifest_json: String,
        source: String,
        timeout_ms: u64,
    ) -> Result<Arc<JsExtension>, JsExtensionError> {
        let limits = RuntimeLimits {
            timeout_ms: if timeout_ms == 0 { 30_000 } else { timeout_ms },
            ..RuntimeLimits::default()
        };
        Ok(Arc::new(JsExtension {
            inner: self.inner.load(&manifest_json, &source, limits)?,
        }))
    }

    pub fn settings(&self, extension_id: String) -> Result<String, JsExtensionError> {
        Ok(serde_json::Value::Object(self.inner.settings(&extension_id)?).to_string())
    }

    pub fn set_setting(
        &self,
        extension_id: String,
        key: String,
        value_json: String,
    ) -> Result<(), JsExtensionError> {
        let value = serde_json::from_str(&value_json)
            .map_err(|error| JsExtensionError::InvalidInput(error.to_string()))?;
        self.inner
            .set_setting(&extension_id, &key, value)
            .map_err(Into::into)
    }

    pub fn remove_setting(
        &self,
        extension_id: String,
        key: String,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .remove_setting(&extension_id, &key)
            .map_err(Into::into)
    }

    pub fn set_allow_private_network(&self, allow: bool) -> Result<(), JsExtensionError> {
        self.inner
            .set_allow_private_network(allow)
            .map_err(Into::into)
    }

    pub fn set_network_compatibility_options(
        &self,
        allow_http: bool,
        insecure_tls: bool,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .set_network_compatibility_options(allow_http, insecure_tls)
            .map_err(Into::into)
    }

    pub fn cleanup_connections(&self) -> Result<(), JsExtensionError> {
        self.inner.cleanup_connections().map_err(Into::into)
    }

    pub fn set_allowed_download_directories(
        &self,
        directories: Vec<String>,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .set_allowed_download_directories(
                &directories
                    .into_iter()
                    .map(std::path::PathBuf::from)
                    .collect::<Vec<_>>(),
            )
            .map_err(Into::into)
    }

    pub fn grant_download_directories(
        &self,
        directories: Vec<String>,
    ) -> Result<Arc<DownloadDirectoryScope>, JsExtensionError> {
        let grants = directories
            .iter()
            .map(|path| {
                self.inner
                    .grant_temporary_download_directory(Path::new(path))
            })
            .collect::<Result<Vec<_>, _>>()
            .map_err(JsExtensionError::Storage)?;
        Ok(Arc::new(DownloadDirectoryScope {
            grants: Mutex::new(Some(grants)),
        }))
    }

    pub fn pending_auth(&self, extension_id: String) -> Result<String, JsExtensionError> {
        Ok(self
            .inner
            .pending_auth(&extension_id)?
            .map(|pending| serde_json::to_string(&pending).expect("pending auth JSON"))
            .unwrap_or_default())
    }

    pub fn set_runtime_state(&self, raw: String) -> Result<(), JsExtensionError> {
        self.inner.set_runtime_state(&raw).map_err(Into::into)
    }

    pub fn set_session_grant(
        &self,
        extension_id: String,
        grant: String,
    ) -> Result<(), JsExtensionError> {
        let grant = zeroize::Zeroizing::new(grant);
        self.inner
            .set_session_grant(&extension_id, &grant)
            .map_err(Into::into)
    }

    pub fn all_pending_auth(&self) -> Result<String, JsExtensionError> {
        Ok(serde_json::to_string(&self.inner.all_pending_auth()?).expect("pending auth JSON"))
    }

    pub fn clear_pending_auth(&self, extension_id: String) -> Result<(), JsExtensionError> {
        self.inner
            .clear_pending_auth(&extension_id)
            .map_err(Into::into)
    }

    pub fn resolve_callback_state(&self, state: String) -> Result<String, JsExtensionError> {
        self.inner
            .resolve_callback_state(&state, false)
            .map_err(Into::into)
    }

    pub fn consume_callback_state(&self, state: String) -> Result<String, JsExtensionError> {
        self.inner
            .resolve_callback_state(&state, true)
            .map_err(Into::into)
    }

    pub fn set_auth_code(
        &self,
        extension_id: String,
        code: String,
    ) -> Result<(), JsExtensionError> {
        let code = zeroize::Zeroizing::new(code);
        self.inner
            .set_auth_code(&extension_id, &code)
            .map_err(Into::into)
    }

    pub fn set_auth_tokens(
        &self,
        extension_id: String,
        access_token: String,
        refresh_token: String,
        expires_in: i64,
    ) -> Result<(), JsExtensionError> {
        let access_token = zeroize::Zeroizing::new(access_token);
        let refresh_token = zeroize::Zeroizing::new(refresh_token);
        self.inner
            .set_auth_tokens(&extension_id, &access_token, &refresh_token, expires_in)
            .map_err(Into::into)
    }

    pub fn is_authenticated(&self, extension_id: String) -> Result<bool, JsExtensionError> {
        self.inner
            .is_authenticated(&extension_id)
            .map_err(Into::into)
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }
}
