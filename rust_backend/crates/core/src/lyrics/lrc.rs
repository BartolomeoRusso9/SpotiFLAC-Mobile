use super::{LyricsLine, LyricsResponse};
use crate::matching::lowercase;
use regex::Regex;
use std::sync::LazyLock;

static TIMED_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\[([0-9]{2}):([0-9]{2})\.([0-9]{2,3})\](.*)").unwrap());
static METADATA: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^\[[a-z][a-z0-9_]*:.*\]$").unwrap());
static BACKGROUND: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^\[bg:(.*)\]$").unwrap());
static LEADING_TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\[[0-9]{1,3}:[0-9]{1,2}(?:[.:][0-9]{1,3})?\]").unwrap());
static INLINE_TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"<[0-9]{1,3}:[0-9]{1,2}(?:[.:][0-9]{1,3})?>").unwrap());
static INSTRUMENTAL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^\[instrumental:true\]$").unwrap());

pub fn is_instrumental_marker(raw: &str) -> bool {
    INSTRUMENTAL.is_match(raw.trim())
}

/// Headers, empty timestamps and empty vocal markers are not embedded lyrics.
pub fn has_usable_content(raw: &str) -> bool {
    if is_instrumental_marker(raw) {
        return true;
    }
    for line in raw.split('\n') {
        let mut cleaned = line.trim();
        if cleaned.is_empty() {
            continue;
        }
        if let Some(background) = BACKGROUND.captures(cleaned) {
            cleaned = background.get(1).unwrap().as_str().trim();
        } else if METADATA.is_match(cleaned) {
            continue;
        }
        while let Some(timestamp) = LEADING_TIME.find(cleaned) {
            cleaned = cleaned[timestamp.end()..].trim();
        }
        let without_inline = INLINE_TIME.replace_all(cleaned, "");
        cleaned = without_inline.trim();
        let lower = lowercase(cleaned);
        if lower.starts_with("v1:") || lower.starts_with("v2:") {
            cleaned = cleaned[3..].trim();
        }
        if !cleaned.is_empty() {
            return true;
        }
    }
    false
}

pub fn parse_synced(raw: &str) -> Option<Vec<LyricsLine>> {
    let mut lines: Vec<LyricsLine> = Vec::new();
    for line in raw.split('\n').map(str::trim) {
        if line.is_empty() {
            continue;
        }
        if line.starts_with("[bg:")
            && let Some(previous) = lines.last_mut()
        {
            previous.words.push('\n');
            previous.words.push_str(line);
            continue;
        }
        if let Some(captures) = TIMED_LINE.captures(line) {
            let words = captures[4].trim();
            if words.is_empty() {
                continue;
            }
            let minutes = captures[1].parse::<i64>().unwrap();
            let seconds = captures[2].parse::<i64>().unwrap();
            let mut fraction = captures[3].parse::<i64>().unwrap();
            if captures[3].len() == 2 {
                fraction *= 10;
            }
            lines.push(LyricsLine {
                start_time_ms: minutes * 60_000 + seconds * 1000 + fraction,
                words: words.into(),
                end_time_ms: 0,
            });
        }
    }
    for index in 1..lines.len() {
        lines[index - 1].end_time_ms = lines[index].start_time_ms;
    }
    if let Some(last) = lines.last_mut() {
        last.end_time_ms = last.start_time_ms + 5000;
    }
    (!lines.is_empty()).then_some(lines)
}

pub fn plain_text_lines(raw: &str) -> Option<Vec<LyricsLine>> {
    let lines: Vec<_> = raw
        .split('\n')
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| LyricsLine {
            words: line.into(),
            ..LyricsLine::default()
        })
        .collect();
    (!lines.is_empty()).then_some(lines)
}

pub fn plain_from_timed_lines(lines: &[LyricsLine]) -> String {
    lines
        .iter()
        .map(|line| line.words.trim())
        .filter(|words| !words.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn timestamp_inline(ms: i64) -> String {
    let seconds = ms / 1000;
    format!(
        "{:02}:{:02}.{:02}",
        seconds / 60,
        seconds % 60,
        ms % 1000 / 10
    )
}

pub fn timestamp(ms: i64) -> String {
    format!("[{}]", timestamp_inline(ms))
}

pub fn source_uses_proxy(source: &str) -> bool {
    let source = lowercase(source.trim());
    !source.is_empty()
        && ![
            "lrclib",
            "kugou direct",
            "qq music direct",
            "genius direct",
            "extension:",
            "heuristic",
        ]
        .iter()
        .any(|prefix| source.starts_with(prefix))
}

pub fn extract_source(raw: &str) -> String {
    for line in raw.split('\n').map(str::trim) {
        if !lowercase(line).starts_with("[by:") {
            continue;
        }
        let Some((_, source)) = line.split_once("(source: ") else {
            return String::new();
        };
        let source = source.trim();
        let source = source.strip_suffix(']').unwrap_or(source);
        return source.strip_suffix(')').unwrap_or(source).trim().into();
    }
    String::new()
}

pub fn with_metadata(lyrics: &LyricsResponse, track: &str, artist: &str) -> String {
    if lyrics.lines().is_empty() {
        return String::new();
    }
    let source = if lyrics.source.trim().is_empty() {
        lyrics.provider.trim()
    } else {
        lyrics.source.trim()
    };
    let credit = if source_uses_proxy(source) {
        "SpotiFLAC-Mobile via Paxsenix API"
    } else {
        "SpotiFLAC-Mobile"
    };
    let mut output = format!("[ti:{track}]\n[ar:{artist}]\n[by:{credit}");
    if !source.is_empty() {
        output.push_str(&format!(" (source: {source})"));
    }
    output.push_str("]\n\n");
    for line in lyrics.lines() {
        if line.words.is_empty() {
            continue;
        }
        if lyrics.sync_type == "LINE_SYNCED" {
            output.push_str(&timestamp(line.start_time_ms));
        }
        output.push_str(&line.words);
        output.push('\n');
    }
    output
}
