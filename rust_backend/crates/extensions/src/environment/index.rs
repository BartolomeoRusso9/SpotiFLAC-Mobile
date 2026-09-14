use super::{EnvironmentError, ExtensionEnvironment};
use spotiflac_core::isrc::{IndexCache, IndexFiles, NativeFiles, parse_tracks};
use std::sync::atomic::Ordering;

type Check<'a> = &'a (dyn Fn() -> Result<(), String> + Sync);

impl ExtensionEnvironment {
    fn with_index<T>(
        &self,
        check: Check<'_>,
        operation: impl FnOnce(&IndexCache, &NativeFiles, Check<'_>) -> Result<T, String>,
    ) -> Result<T, EnvironmentError> {
        let _operation = self.enter()?;
        let guarded = || {
            if self.closed.load(Ordering::Acquire) {
                Err("extension environment closed".into())
            } else {
                check()
            }
        };
        guarded().map_err(EnvironmentError::Index)?;
        let result =
            operation(&self.isrc, &NativeFiles, &guarded).map_err(EnvironmentError::Index)?;
        guarded().map_err(EnvironmentError::Index)?;
        Ok(result)
    }

    /// Trusted native entry points share the SDK's index, while JavaScript uses
    /// a scoped IndexFiles adapter and revalidates native directory grants.
    pub fn prebuild_isrc_index(
        &self,
        directory: &str,
        check: Check<'_>,
    ) -> Result<(), EnvironmentError> {
        self.with_index(check, |cache, files, check| {
            cache.prebuild(directory, files, check)
        })
    }

    pub fn check_isrc_exists(
        &self,
        directory: &str,
        isrc: &str,
        check: Check<'_>,
    ) -> Result<String, EnvironmentError> {
        self.with_index(check, |cache, files, check| {
            cache.check(directory, isrc, files, check)
        })
    }

    pub fn add_to_isrc_index(
        &self,
        directory: &str,
        isrc: &str,
        path: &str,
        check: Check<'_>,
    ) -> Result<(), EnvironmentError> {
        self.with_index(check, |cache, files, check| {
            cache.add(directory, isrc, path, files, check)
        })
    }

    pub fn check_files_exist_parallel(
        &self,
        directory: &str,
        tracks_json: &str,
        check: Check<'_>,
    ) -> Result<String, EnvironmentError> {
        self.with_index(check, |cache, files, check| {
            if tracks_json.len() > 8 * 1024 * 1024 {
                return Err("tracks JSON exceeds 8 MiB limit".into());
            }
            let tracks = parse_tracks(tracks_json)?;
            let results = cache.check_batch(directory, &tracks, files, check)?;
            serde_json::to_string(&results).map_err(|error| error.to_string())
        })
    }

    pub fn invalidate_isrc_cache(&self, directory: &str) -> Result<(), EnvironmentError> {
        let _operation = self.enter()?;
        self.isrc.invalidate(directory);
        Ok(())
    }

    pub fn check_file_exists(&self, path: &str) -> Result<bool, EnvironmentError> {
        let _operation = self.enter()?;
        NativeFiles
            .stat(path)
            .map(|stamp| stamp.is_some_and(|stamp| !stamp.directory && stamp.size > 0))
            .map_err(EnvironmentError::Index)
    }
}
