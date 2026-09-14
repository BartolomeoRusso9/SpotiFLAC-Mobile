use crate::cancellation::RequestLease;
use crate::extensions::{ExtensionEnvironment, JsExtensionError};
use std::sync::Arc;

fn check(lease: &Option<Arc<RequestLease>>) -> Result<(), String> {
    lease.as_ref().map_or(Ok(()), |lease| {
        lease
            .inner
            .check_active()
            .map_err(|error| error.to_string())
    })
}

#[uniffi::export]
impl ExtensionEnvironment {
    pub fn prebuild_isrc_index(
        &self,
        directory: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .prebuild_isrc_index(&directory, &|| check(&lease))
            .map_err(Into::into)
    }

    pub fn check_isrc_exists(
        &self,
        directory: String,
        isrc: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<String, JsExtensionError> {
        self.inner
            .check_isrc_exists(&directory, &isrc, &|| check(&lease))
            .map_err(Into::into)
    }

    pub fn add_to_isrc_index(
        &self,
        directory: String,
        isrc: String,
        path: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .add_to_isrc_index(&directory, &isrc, &path, &|| check(&lease))
            .map_err(Into::into)
    }

    pub fn check_files_exist_parallel(
        &self,
        directory: String,
        tracks_json: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<String, JsExtensionError> {
        self.inner
            .check_files_exist_parallel(&directory, &tracks_json, &|| check(&lease))
            .map_err(Into::into)
    }

    pub fn invalidate_isrc_cache(&self, directory: String) -> Result<(), JsExtensionError> {
        self.inner
            .invalidate_isrc_cache(&directory)
            .map_err(Into::into)
    }

    pub fn check_file_exists(&self, path: String) -> Result<bool, JsExtensionError> {
        self.inner.check_file_exists(&path).map_err(Into::into)
    }
}
