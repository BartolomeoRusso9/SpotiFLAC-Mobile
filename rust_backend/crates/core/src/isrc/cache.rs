use crate::matching::uppercase;
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, TryLockError, Weak};
use std::time::{Duration, Instant};

type Check<'a> = &'a (dyn Fn() -> Result<(), String> + Sync);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileStamp {
    pub path: String,
    pub size: u64,
    pub modified_ns: i128,
    pub directory: bool,
}

/// The native owner supplies filesystem access. A cache hit never grants access
/// to a path: adapters must validate directory authority before each operation.
pub trait IndexFiles: Sync {
    /// Return entries in lexical depth-first walk order, preserving directory
    /// boundaries rather than sorting the complete path strings afterward.
    fn list(&self, directory: &str, check: Check<'_>) -> Result<Vec<FileStamp>, String>;
    fn read(&self, path: &str, check: Check<'_>) -> Result<String, String>;
    fn stat(&self, path: &str) -> Result<Option<FileStamp>, String>;
}

#[derive(Clone)]
struct FileEntry {
    stamp: FileStamp,
    isrc: String,
}

struct Index {
    entries: BTreeMap<String, String>,
    files: BTreeMap<String, FileEntry>,
    built_at: Instant,
}

pub struct IndexCache {
    indexes: Mutex<BTreeMap<String, Arc<Mutex<Index>>>>,
    builders: Mutex<BTreeMap<String, Weak<Mutex<()>>>>,
    ttl: Duration,
}

impl Default for IndexCache {
    fn default() -> Self {
        Self::with_ttl(Duration::from_secs(5 * 60))
    }
}

impl IndexCache {
    pub fn with_ttl(ttl: Duration) -> Self {
        Self {
            indexes: Mutex::default(),
            builders: Mutex::default(),
            ttl,
        }
    }

    fn cached(&self, directory: &str) -> Option<Arc<Mutex<Index>>> {
        self.indexes
            .lock()
            .expect("ISRC cache lock")
            .get(directory)
            .cloned()
    }

    fn fresh(&self, directory: &str) -> Option<Arc<Mutex<Index>>> {
        self.cached(directory)
            .filter(|index| index.lock().expect("ISRC index lock").built_at.elapsed() < self.ttl)
    }

    fn index(
        &self,
        directory: &str,
        files: &dyn IndexFiles,
        force: bool,
        check: Check<'_>,
    ) -> Result<Arc<Mutex<Index>>, String> {
        check()?;
        if !force && let Some(index) = self.fresh(directory) {
            return Ok(index);
        }
        let builder = {
            let mut builders = self.builders.lock().expect("ISRC builders lock");
            let entry = builders.entry(directory.into()).or_default();
            entry.upgrade().unwrap_or_else(|| {
                let lock = Arc::new(Mutex::new(()));
                *entry = Arc::downgrade(&lock);
                lock
            })
        };
        let _building = wait_for_builder(&builder, check)?;
        if !force && let Some(index) = self.fresh(directory) {
            return Ok(index);
        }
        let previous = self
            .cached(directory)
            .map(|index| index.lock().expect("ISRC index lock").files.clone())
            .unwrap_or_default();
        let mut index = Index {
            entries: BTreeMap::new(),
            files: BTreeMap::new(),
            built_at: Instant::now(),
        };
        let mut changed = Vec::new();
        if !directory.is_empty() {
            let listed = files.list(directory, check)?;
            for stamp in listed {
                check()?;
                if stamp.directory || !super::supported(&stamp.path) {
                    continue;
                }
                if let Some(entry) = previous.get(&stamp.path)
                    && entry.stamp == stamp
                {
                    if !entry.isrc.is_empty() {
                        index.entries.insert(entry.isrc.clone(), stamp.path.clone());
                    }
                    index.files.insert(stamp.path.clone(), entry.clone());
                } else {
                    changed.push(stamp);
                }
            }
        }
        let next = AtomicUsize::new(0);
        let values = Mutex::new(vec![String::new(); changed.len()]);
        std::thread::scope(|scope| {
            let handles = (0..changed.len().min(4))
                .map(|_| {
                    scope.spawn(|| {
                        loop {
                            check()?;
                            let position = next.fetch_add(1, Ordering::Relaxed);
                            let Some(stamp) = changed.get(position) else {
                                break;
                            };
                            let isrc = uppercase(&files.read(&stamp.path, check)?);
                            values.lock().expect("ISRC parse results lock")[position] = isrc;
                        }
                        Ok::<_, String>(())
                    })
                })
                .collect::<Vec<_>>();
            for handle in handles {
                handle
                    .join()
                    .map_err(|_| "ISRC reader worker panicked".to_owned())??;
            }
            Ok::<_, String>(())
        })?;
        // Changed files are applied after reused entries, in walk order, just
        // as Go does after joining its four parsing workers.
        for (stamp, isrc) in changed
            .into_iter()
            .zip(values.into_inner().expect("ISRC parse results lock"))
        {
            check()?;
            if !isrc.is_empty() {
                index.entries.insert(isrc.clone(), stamp.path.clone());
            }
            index
                .files
                .insert(stamp.path.clone(), FileEntry { stamp, isrc });
        }
        check()?;
        let index = Arc::new(Mutex::new(index));
        if !directory.is_empty() {
            self.indexes
                .lock()
                .expect("ISRC cache lock")
                .insert(directory.into(), Arc::clone(&index));
        }
        Ok(index)
    }

    pub fn check(
        &self,
        directory: &str,
        isrc: &str,
        files: &dyn IndexFiles,
        check: Check<'_>,
    ) -> Result<String, String> {
        check()?;
        if directory.is_empty() || isrc.is_empty() {
            return Ok(String::new());
        }
        let index = self.index(directory, files, false, check)?;
        let key = uppercase(isrc);
        let path = index
            .lock()
            .expect("ISRC index lock")
            .entries
            .get(&key)
            .cloned();
        let Some(path) = path else {
            return Ok(String::new());
        };
        check()?;
        let exists = files
            .stat(&path)?
            .is_some_and(|stamp| !stamp.directory && stamp.size > 0);
        check()?;
        if exists {
            Ok(path)
        } else {
            index.lock().expect("ISRC index lock").entries.remove(&key);
            Ok(String::new())
        }
    }

    pub fn add(
        &self,
        directory: &str,
        isrc: &str,
        path: &str,
        files: &dyn IndexFiles,
        check: Check<'_>,
    ) -> Result<(), String> {
        check()?;
        if directory.is_empty() || isrc.is_empty() || path.is_empty() {
            return Ok(());
        }
        if let Some(index) = self.cached(directory) {
            let stamp = files.stat(path)?;
            check()?;
            let mut index = index.lock().expect("ISRC index lock");
            let isrc = uppercase(isrc);
            index.entries.insert(isrc.clone(), path.into());
            if let Some(stamp) = stamp {
                index.files.insert(path.into(), FileEntry { stamp, isrc });
            }
            index.built_at = Instant::now();
        }
        Ok(())
    }

    pub fn invalidate(&self, directory: &str) {
        self.indexes
            .lock()
            .expect("ISRC cache lock")
            .remove(directory);
    }

    pub fn clear(&self) {
        self.indexes.lock().expect("ISRC cache lock").clear();
    }

    pub fn prebuild(
        &self,
        directory: &str,
        files: &dyn IndexFiles,
        check: Check<'_>,
    ) -> Result<(), String> {
        if directory.is_empty() {
            return Err("output directory is required".into());
        }
        self.index(directory, files, true, check).map(|_| ())
    }

    pub fn check_batch(
        &self,
        directory: &str,
        tracks: &[TrackQuery],
        files: &dyn IndexFiles,
        check: Check<'_>,
    ) -> Result<Vec<TrackExistence>, String> {
        let index = self.index(directory, files, false, check)?;
        let index = index.lock().expect("ISRC index lock");
        tracks
            .iter()
            .map(|track| {
                check()?;
                // Go's batch API deliberately trusts the cache without stat calls.
                let path = index
                    .entries
                    .get(&uppercase(&track.isrc))
                    .filter(|_| !track.isrc.is_empty());
                Ok(TrackExistence {
                    isrc: track.isrc.clone(),
                    exists: path.is_some(),
                    file_path: path.cloned().unwrap_or_default(),
                    track_name: track.track_name.clone(),
                    artist_name: track.artist_name.clone(),
                })
            })
            .collect()
    }
}

fn wait_for_builder<'a>(
    builder: &'a Mutex<()>,
    check: Check<'_>,
) -> Result<MutexGuard<'a, ()>, String> {
    loop {
        check()?;
        match builder.try_lock() {
            Ok(guard) => return Ok(guard),
            Err(TryLockError::Poisoned(error)) => return Ok(error.into_inner()),
            Err(TryLockError::WouldBlock) => std::thread::sleep(Duration::from_millis(5)),
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct TrackQuery {
    pub isrc: String,
    pub track_name: String,
    pub artist_name: String,
}

impl<'de> Deserialize<'de> for TrackQuery {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor;
        impl<'de> serde::de::Visitor<'de> for Visitor {
            type Value = TrackQuery;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("a track object")
            }
            fn visit_map<M: serde::de::MapAccess<'de>>(
                self,
                mut map: M,
            ) -> Result<TrackQuery, M::Error> {
                let mut track = TrackQuery::default();
                while let Some(key) = map.next_key::<String>()? {
                    let field = if equal_field(&key, "isrc") {
                        Some(&mut track.isrc)
                    } else if equal_field(&key, "track_name") {
                        Some(&mut track.track_name)
                    } else if equal_field(&key, "artist_name") {
                        Some(&mut track.artist_name)
                    } else {
                        None
                    };
                    if let Some(field) = field {
                        if let Some(value) = map.next_value::<Option<String>>()? {
                            *field = value;
                        }
                    } else {
                        map.next_value::<serde::de::IgnoredAny>()?;
                    }
                }
                Ok(track)
            }
        }
        deserializer.deserialize_map(Visitor)
    }
}

pub fn parse_tracks(json: &str) -> Result<Vec<TrackQuery>, String> {
    // Go matches the snake_case JSON tags, folds field-name case, and ignores
    // null string values without overwriting an earlier duplicate field.
    serde_json::from_str::<Option<Vec<Option<TrackQuery>>>>(&crate::text::json_surrogates(json))
        .map(|tracks| {
            tracks
                .unwrap_or_default()
                .into_iter()
                .map(Option::unwrap_or_default)
                .collect()
        })
        .map_err(|error| format!("failed to parse tracks JSON: {error}"))
}

fn equal_field(value: &str, target: &str) -> bool {
    value.eq_ignore_ascii_case(target)
        || (value.chars().count() == target.len()
            && value.chars().zip(target.chars()).all(|(actual, expected)| {
                actual.eq_ignore_ascii_case(&expected)
                    || (actual == 'ſ' && expected == 's')
                    || (actual == 'K' && expected == 'k')
            }))
}

#[derive(Debug, Serialize)]
pub struct TrackExistence {
    pub isrc: String,
    pub exists: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub file_path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub track_name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub artist_name: String,
}
