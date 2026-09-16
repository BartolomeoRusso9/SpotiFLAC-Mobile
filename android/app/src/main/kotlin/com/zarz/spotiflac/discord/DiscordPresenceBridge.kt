package com.zarz.spotiflac.discord

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.zarz.spotiflac.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal object DiscordNative {
    external fun start(appId: Long)
    external fun update(title: String, artist: String, album: String, cover: String, start: Long, end: Long)
    external fun clear()
    external fun stop()
    external fun poll(): String
}

/** Official client RPC only. No user tokens, custom Gateway, or background login. */
internal object DiscordPresenceBridge {
    private const val APPLICATION_ID = 1549854098801692862L
    private val handler = Handler(Looper.getMainLooper())
    private var loaded = false
    private var enabled = false
    private var status = "disabled"
    private var channel: MethodChannel? = null
    private val pump = object : Runnable {
        override fun run() {
            if (!enabled) return
            val next = DiscordNative.poll()
            if (next != status) {
                status = next
                channel?.invokeMethod("status", status)
            }
            if (status != "unavailable") handler.postDelayed(this, 250)
        }
    }

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "com.zarz.spotiflac/discord").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> result.success(configure(activity, call.argument<Boolean>("enabled") == true))
                        "update" -> {
                            if (enabled) {
                                DiscordNative.start(APPLICATION_ID)
                                val cover = call.argument<String>("cover").orEmpty()
                                DiscordNative.update(
                                    call.argument<String>("title").orEmpty().take(128),
                                    call.argument<String>("artist").orEmpty().take(128),
                                    call.argument<String>("album").orEmpty().take(128),
                                    cover.takeIf { it.startsWith("https://") && it.length <= 300 }.orEmpty(),
                                    call.argument<Number>("start")?.toLong()?.coerceAtLeast(0) ?: 0,
                                    call.argument<Number>("end")?.toLong()?.coerceAtLeast(0) ?: 0,
                                )
                                handler.removeCallbacks(pump)
                                handler.post(pump)
                            }
                            result.success(null)
                        }
                        "clear" -> {
                            if (enabled) {
                                handler.removeCallbacks(pump)
                                DiscordNative.stop()
                                status = "ready"
                                channel.invokeMethod("status", status)
                            }
                            result.success(null)
                        }
                        "status" -> result.success(status)
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("discord_unavailable", "Discord presence is unavailable", null)
                } catch (error: LinkageError) {
                    result.error("discord_unavailable", "Discord SDK could not be loaded", null)
                }
            }
        }
        if (loaded) setActivity(activity)
    }

    private fun setActivity(activity: Activity) {
        Class.forName("com.discord.socialsdk.DiscordSocialSdkInit")
            .getMethod("setEngineActivity", Activity::class.java).invoke(null, activity)
    }

    internal fun configure(activity: Activity, requested: Boolean): String {
        check(Looper.myLooper() == Looper.getMainLooper())
        handler.removeCallbacks(pump)
        enabled = false
        if (loaded) DiscordNative.stop()
        if (!requested) {
            status = "disabled"
            return status
        }
        if (!BuildConfig.HAS_DISCORD_SDK) return "sdk_unavailable".also { status = it }
        if (!isDiscordInstalled(activity)) return "discord_missing".also { status = it }
        if (!loaded) {
            System.loadLibrary("spotiflac_discord")
            loaded = true
        }
        setActivity(activity)
        enabled = true
        status = "ready"
        return status
    }

    private fun isDiscordInstalled(context: Context): Boolean =
        context.packageManager.getLaunchIntentForPackage("com.discord") != null
}
