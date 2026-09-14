use super::{LyricsResponse, json, lrc};
use serde::Serialize;
use serde_json::value::RawValue;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Serialize)]
pub struct PaxDetail {
    pub text: String,
    pub part: bool,
    pub timestamp: Option<isize>,
    pub endtime: Option<isize>,
}
json::go_deserialize!(PaxDetail {
    "text" => text, "part" => part, "timestamp" => timestamp, "endtime" => endtime,
});

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PaxLine {
    pub text: Option<Vec<PaxDetail>>,
    pub timestamp: isize,
    pub opposite_turn: bool,
    pub background: bool,
    pub background_text: Option<Vec<PaxDetail>>,
    pub endtime: isize,
}
json::go_deserialize!(PaxLine {
    "text" => text, "timestamp" => timestamp, "oppositeturn" => opposite_turn,
    "background" => background, "backgroundtext" => background_text, "endtime" => endtime,
});

#[derive(Default)]
struct ApplePayload {
    kind: String,
    content: Option<Vec<PaxLine>>,
    elrc: String,
    elrc_multi_person: String,
    plain: String,
    ttml_content: String,
}
json::go_deserialize!(ApplePayload {
    "type" => kind, "content" => content, "elrc" => elrc,
    "elrcmultiperson" => elrc_multi_person, "plain" => plain, "ttmlcontent" => ttml_content,
});

#[derive(Default)]
struct ProxyPayload {
    kind: String,
    content: Option<Vec<PaxLine>>,
    lyrics: Option<Vec<PaxLine>>,
    lyrics_text: String,
    plain_lyrics: String,
}
json::go_deserialize!(ProxyPayload {
    "type" => kind, "content" => content, "lyrics" => lyrics,
    "lyrics_text" => lyrics_text, "plain_lyrics" => plain_lyrics,
});

fn append_detail(output: &mut String, details: &[PaxDetail], word_timing: bool) {
    let mut last_start = String::new();
    for detail in details {
        if word_timing && let Some(time) = detail.timestamp {
            let start = format!("<{}>", lrc::timestamp_inline(time as i64));
            if start != last_start {
                output.push_str(&start);
                last_start = start;
            }
        }
        output.push_str(&detail.text);
        if !detail.part {
            output.push(' ');
        }
        if word_timing && let Some(time) = detail.endtime {
            output.push_str(&format!("<{}>", lrc::timestamp_inline(time as i64)));
        }
    }
}

pub fn format_pax_content(
    kind: &str,
    lines: &[PaxLine],
    multi_person: bool,
    word_timing: bool,
) -> String {
    let mut output = String::new();
    for (index, line) in lines.iter().enumerate() {
        if index > 0 {
            output.push('\n');
        }
        if json::field_name(kind) == "syllable" {
            output.push_str(&lrc::timestamp(line.timestamp as i64));
            if multi_person {
                output.push_str(if line.opposite_turn { "v2:" } else { "v1:" });
            }
            append_detail(
                &mut output,
                line.text.as_deref().unwrap_or_default(),
                word_timing,
            );
            if line.background
                && multi_person
                && let Some(background) = line
                    .background_text
                    .as_ref()
                    .filter(|lines| !lines.is_empty())
            {
                output.push_str("\n[bg:");
                append_detail(&mut output, background, word_timing);
                output.push(']');
            }
        } else if let Some(text) = line.text.as_ref().and_then(|text| text.first()) {
            output.push_str(&lrc::timestamp(line.timestamp as i64));
            output.push_str(&text.text);
        }
    }
    output.trim().into()
}

pub fn format_apple(raw: &str, multi_person: bool, word_timing: bool) -> Result<String, String> {
    if let Ok(Some(value)) = json::decode::<Option<String>>(raw)
        && !value.trim().is_empty()
    {
        return Ok(value.trim().into());
    }
    if let Ok(value) = json::decode::<ApplePayload>(raw)
        && (value.content.is_some()
            || [
                &value.elrc_multi_person,
                &value.elrc,
                &value.plain,
                &value.ttml_content,
            ]
            .iter()
            .any(|value| !value.trim().is_empty()))
    {
        if word_timing && multi_person && !value.elrc_multi_person.trim().is_empty() {
            return Ok(value.elrc_multi_person.trim().into());
        }
        if word_timing && !value.elrc.trim().is_empty() {
            return Ok(value.elrc.trim().into());
        }
        let content = value.content.as_deref().unwrap_or_default();
        if !value.plain.trim().is_empty() && content.is_empty() {
            return Ok(value.plain.trim().into());
        }
        if content.is_empty() {
            return Err("unsupported apple music lyrics payload".into());
        }
        return Ok(format_pax_content(
            &value.kind,
            content,
            multi_person,
            word_timing,
        ));
    }
    if let Ok(Some(lines)) = json::decode::<Option<Vec<PaxLine>>>(raw)
        && !lines.is_empty()
    {
        return Ok(format_pax_content(
            "Syllable",
            &lines,
            multi_person,
            word_timing,
        ));
    }
    Err("failed to parse pax lyrics response".into())
}

/// Failure strings describe unavailable proxy payloads, not an absent track.
pub fn parse_proxy(
    raw: &str,
    provider: &str,
    multi_person: bool,
) -> Result<LyricsResponse, String> {
    if let Ok(value) = json::decode::<Option<String>>(raw) {
        let value = value.unwrap_or_default();
        if value.trim().is_empty() {
            return Err(format!("{provider} returned empty lyrics"));
        }
        return Ok(LyricsResponse::from_text(value.trim(), provider, provider));
    }
    // Go checks these aliases through json.RawMessage. An unused number may
    // exceed float64's range without invalidating an otherwise usable payload.
    if let Ok(value) = json::decode::<BTreeMap<String, Box<RawValue>>>(raw) {
        for key in ["lyrics", "lyric", "lyrics_text", "plain_lyrics"] {
            if let Some(text) = value
                .get(key)
                .and_then(|value| json::decode::<Option<String>>(value.get()).ok().flatten())
                .filter(|value| !value.trim().is_empty())
            {
                return Ok(LyricsResponse::from_text(text.trim(), provider, provider));
            }
        }
    }
    if let Ok(value) = json::decode::<ProxyPayload>(raw) {
        let content = value.content.as_deref().unwrap_or_default();
        let lyrics = value.lyrics.as_deref().unwrap_or_default();
        let text = if !value.lyrics_text.trim().is_empty() {
            Some(value.lyrics_text)
        } else if !lyrics.is_empty() {
            Some(format_pax_content("Syllable", lyrics, multi_person, true))
        } else if !content.is_empty() {
            Some(format_pax_content(
                if value.kind.is_empty() {
                    "Syllable"
                } else {
                    &value.kind
                },
                content,
                multi_person,
                true,
            ))
        } else if !value.plain_lyrics.trim().is_empty() {
            Some(value.plain_lyrics)
        } else {
            None
        };
        if let Some(text) = text {
            return Ok(LyricsResponse::from_text(&text, provider, provider));
        }
    }
    let raw = raw.trim();
    if !raw.is_empty() && !raw.starts_with(['{', '[']) {
        return Ok(LyricsResponse::from_text(raw, provider, provider));
    }
    if json::decode::<Box<RawValue>>(raw).is_ok() {
        return Err(format!(
            "{provider} returned a response without usable lyrics"
        ));
    }
    Err(format!("failed to decode {provider} lyrics response"))
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KpoeSyllable {
    pub text: String,
    pub time: f64,
    pub duration: f64,
    pub is_background: bool,
}
json::go_deserialize!(KpoeSyllable {
    "text" => text, "time" => time, "duration" => duration, "isbackground" => is_background,
});

#[derive(Clone, Debug, Default, Serialize)]
pub struct KpoeLine {
    pub time: f64,
    pub duration: f64,
    pub text: String,
    pub syllabus: Option<Vec<KpoeSyllable>>,
}
json::go_deserialize!(KpoeLine {
    "time" => time, "duration" => duration, "text" => text, "syllabus" => syllabus,
});

#[derive(Clone, Debug, Default, Serialize)]
pub struct KpoeResponse {
    #[serde(rename = "type")]
    pub kind: String,
    pub lyrics: Option<Vec<KpoeLine>>,
}
json::go_deserialize!(KpoeResponse { "type" => kind, "lyrics" => lyrics, });

pub fn format_kpoe(response: &KpoeResponse, multi_person: bool, word_timing: bool) -> String {
    let words = matches!(
        json::field_name(&response.kind).as_str(),
        "word" | "syllable"
    );
    let mut lines = Vec::new();
    let append = |details: &[&KpoeSyllable]| {
        let mut result = String::new();
        for detail in details {
            result.push_str(&format!(
                "<{}>{}",
                lrc::timestamp_inline(detail.time as i64),
                detail.text
            ));
        }
        result
    };
    for line in response.lyrics.as_deref().unwrap_or_default() {
        let syllabus = line.syllabus.as_deref().unwrap_or_default();
        let timestamp = lrc::timestamp(line.time as i64);
        if words && word_timing && !syllabus.is_empty() {
            let (mut main, mut background): (Vec<_>, Vec<_>) =
                syllabus.iter().partition(|detail| !detail.is_background);
            if main.is_empty() {
                main = syllabus.iter().collect();
                background.clear();
            }
            let mut output = format!("{timestamp}{}", append(&main));
            if multi_person && !background.is_empty() {
                output.push_str(&format!("\n[bg:{}]", append(&background)));
            }
            lines.push(output);
        } else {
            let text = if line.text.trim().is_empty() && !syllabus.is_empty() {
                syllabus
                    .iter()
                    .map(|detail| detail.text.as_str())
                    .collect::<String>()
            } else {
                line.text.clone()
            };
            if !text.trim().is_empty() {
                lines.push(format!("{timestamp}{}", text.trim()));
            }
        }
    }
    lines.join("\n").trim().into()
}
