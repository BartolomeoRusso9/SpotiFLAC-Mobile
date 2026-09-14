use crate::cancellation::{CancellationError, RequestLease};
use spotiflac_core::downloads::DownloadState as CoreState;
use spotiflac_core::progress::{ProgressError, ProgressSubscription};
use std::sync::Arc;

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum DownloadProgressError {
    #[error("download progress registry closed")]
    Closed,
    #[error("download progress subscription closed")]
    SubscriptionClosed,
}

impl From<ProgressError> for DownloadProgressError {
    fn from(error: ProgressError) -> Self {
        match error {
            ProgressError::Closed => Self::Closed,
            ProgressError::SubscriptionClosed => Self::SubscriptionClosed,
        }
    }
}

/// Share one instance between the native download manager and its listeners.
#[derive(uniffi::Object)]
pub struct DownloadState {
    pub(crate) inner: Arc<CoreState>,
}

#[uniffi::export]
impl DownloadState {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Arc::new(CoreState::default()),
        }
    }

    pub fn acquire(&self, item_id: String) -> Result<Arc<RequestLease>, CancellationError> {
        Ok(Arc::new(RequestLease {
            inner: Arc::new(self.inner.acquire(&item_id)?),
        }))
    }

    pub fn cancel_download(&self, item_id: String) -> Result<(), CancellationError> {
        self.inner.cancel(&item_id).map_err(Into::into)
    }

    pub fn cancel_active_downloads(&self) -> Result<Vec<String>, CancellationError> {
        self.inner.cancel_active().map_err(Into::into)
    }

    pub fn reset_download_cancel(&self, item_id: String) -> Result<(), CancellationError> {
        self.inner
            .cancellation
            .reset_if_idle(&item_id)
            .map_err(Into::into)
    }

    pub fn is_cancelled(&self, item_id: String) -> Result<bool, CancellationError> {
        self.inner
            .cancellation
            .is_cancelled(&item_id)
            .map_err(Into::into)
    }

    pub fn init_item_progress(&self, item_id: String) -> Result<(), DownloadProgressError> {
        self.inner.progress.start(&item_id).map_err(Into::into)
    }

    pub fn clear_item_progress(&self, item_id: String) -> Result<(), DownloadProgressError> {
        self.inner.progress.remove(&item_id).map_err(Into::into)
    }

    pub fn clear_all_progress(&self) -> Result<(), DownloadProgressError> {
        self.inner.progress.clear().map_err(Into::into)
    }

    pub fn set_preparing(
        &self,
        item_id: String,
        stage: String,
    ) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .preparing(&item_id, &stage)
            .map_err(Into::into)
    }

    pub fn set_downloading(&self, item_id: String) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .downloading(&item_id)
            .map_err(Into::into)
    }

    pub fn set_total(&self, item_id: String, total: i64) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .set_total(&item_id, total)
            .map_err(Into::into)
    }

    pub fn set_received(
        &self,
        item_id: String,
        received: i64,
    ) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .set_received(&item_id, received)
            .map_err(Into::into)
    }

    pub fn set_received_with_speed(
        &self,
        item_id: String,
        received: i64,
        speed: f64,
    ) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .set_received_with_speed(&item_id, received, speed)
            .map_err(Into::into)
    }

    pub fn set_progress(
        &self,
        item_id: String,
        progress: f64,
        received: i64,
        total: i64,
    ) -> Result<(), DownloadProgressError> {
        self.inner
            .progress
            .set_progress(&item_id, progress, received, total)
            .map_err(Into::into)
    }

    pub fn set_finalizing(&self, item_id: String) -> Result<(), DownloadProgressError> {
        self.inner.progress.finalizing(&item_id).map_err(Into::into)
    }

    pub fn complete_item(&self, item_id: String) -> Result<(), DownloadProgressError> {
        self.inner.progress.complete(&item_id).map_err(Into::into)
    }

    pub fn item_progress(&self, item_id: String) -> Result<String, DownloadProgressError> {
        self.inner.progress.item(&item_id).map_err(Into::into)
    }

    pub fn all_progress(&self) -> Result<String, DownloadProgressError> {
        self.inner.progress.snapshot().map_err(Into::into)
    }

    pub fn progress_delta(&self, since: i64) -> Result<String, DownloadProgressError> {
        self.inner.progress.delta(since).map_err(Into::into)
    }

    pub fn wait_progress_delta(
        &self,
        since: i64,
        timeout_ms: i64,
    ) -> Result<String, DownloadProgressError> {
        self.inner
            .progress
            .wait_delta(since, timeout_ms)
            .map_err(Into::into)
    }

    pub fn subscribe_progress(
        &self,
    ) -> Result<Arc<DownloadProgressSubscription>, DownloadProgressError> {
        Ok(Arc::new(DownloadProgressSubscription {
            inner: self.inner.progress.subscribe()?,
        }))
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }
}

impl Default for DownloadState {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(uniffi::Object)]
pub struct DownloadProgressSubscription {
    inner: ProgressSubscription,
}

#[uniffi::export]
impl DownloadProgressSubscription {
    pub fn wait_delta(&self, since: i64, timeout_ms: i64) -> Result<String, DownloadProgressError> {
        self.inner.wait_delta(since, timeout_ms).map_err(Into::into)
    }

    pub fn stop(&self) {
        self.inner.close();
    }
}
