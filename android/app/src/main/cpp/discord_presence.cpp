// Rich Presence initiative: @itsmegaaa, SpotiFLAC-Mobile #575 / #576.
// Uses the official Social SDK transport instead of a custom user Gateway.
#define DISCORDPP_IMPLEMENTATION
#include <discordpp.h>
#include <jni.h>
#include <memory>
#include <string>

namespace {
// All entry points and SDK callbacks run on Android's main thread.
std::unique_ptr<discordpp::Client> client;
uint64_t generation = 0;
std::string status = "disabled";

std::string utf8(JNIEnv* env, jstring value) {
    if (!value) return {};
    // JNI's modified UTF-8 is not suitable for emoji in track titles.
    const auto length = env->GetStringLength(value);
    const auto* chars = env->GetStringChars(value, nullptr);
    std::string out;
    for (jsize i = 0; i < length; ++i) {
        uint32_t c = chars[i];
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < length &&
            chars[i + 1] >= 0xdc00 && chars[i + 1] <= 0xdfff) {
            c = 0x10000 + ((c - 0xd800) << 10) + (chars[++i] - 0xdc00);
        } else if (c >= 0xd800 && c <= 0xdfff) {
            c = 0xfffd;
        }
        if (c < 0x80) out += static_cast<char>(c);
        else if (c < 0x800) {
            out += static_cast<char>(0xc0 | (c >> 6));
            out += static_cast<char>(0x80 | (c & 0x3f));
        } else if (c < 0x10000) {
            out += static_cast<char>(0xe0 | (c >> 12));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
            out += static_cast<char>(0x80 | (c & 0x3f));
        } else {
            out += static_cast<char>(0xf0 | (c >> 18));
            out += static_cast<char>(0x80 | ((c >> 12) & 0x3f));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
            out += static_cast<char>(0x80 | (c & 0x3f));
        }
    }
    env->ReleaseStringChars(value, chars);
    return out;
}
}

extern "C" JNIEXPORT void JNICALL
Java_com_zarz_spotiflac_discord_DiscordNative_start(JNIEnv*, jobject, jlong appId) {
    if (client) return;
    ++generation;
    client = std::make_unique<discordpp::Client>();
    client->SetApplicationId(static_cast<uint64_t>(appId));
    status = "ready";
}

extern "C" JNIEXPORT void JNICALL
Java_com_zarz_spotiflac_discord_DiscordNative_update(
    JNIEnv* env, jobject, jstring title, jstring artist, jstring album,
    jstring cover, jlong start, jlong end) {
    if (!client) return;
    discordpp::Activity activity;
    activity.SetType(discordpp::ActivityTypes::Listening);
    activity.SetDetails(utf8(env, title));
    activity.SetState(utf8(env, artist));
    discordpp::ActivityTimestamps timestamps;
    timestamps.SetStart(static_cast<uint64_t>(start));
    if (end > start) timestamps.SetEnd(static_cast<uint64_t>(end));
    activity.SetTimestamps(timestamps);
    const auto image = utf8(env, cover);
    if (!image.empty()) {
        discordpp::ActivityAssets assets;
        assets.SetLargeImage(image);
        assets.SetLargeText(utf8(env, album));
        activity.SetAssets(assets);
    }
    const auto current = ++generation;
    status = "updating";
    client->UpdateRichPresence(activity, [current](discordpp::ClientResult result) {
        if (current != generation) return;
        status = result.Successful() ? "sharing" : "unavailable";
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_zarz_spotiflac_discord_DiscordNative_clear(JNIEnv*, jobject) {
    ++generation;
    if (client) client->ClearRichPresence();
    status = client ? "ready" : "disabled";
}

extern "C" JNIEXPORT void JNICALL
Java_com_zarz_spotiflac_discord_DiscordNative_stop(JNIEnv*, jobject) {
    ++generation;
    if (client) client->ClearRichPresence();
    client.reset();
    status = "disabled";
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_zarz_spotiflac_discord_DiscordNative_poll(JNIEnv* env, jobject) {
    discordpp::RunCallbacks();
    return env->NewStringUTF(status.c_str());
}
