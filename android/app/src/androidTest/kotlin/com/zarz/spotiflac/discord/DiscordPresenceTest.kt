package com.zarz.spotiflac.discord

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.zarz.spotiflac.BuildConfig
import com.zarz.spotiflac.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the actual JNI library/SDK in the emulator, without account credentials. */
@RunWith(AndroidJUnit4::class)
class DiscordPresenceTest {
    @Test
    fun testSdkLifecycleAndLateCallbacks() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assumeTrue("Build with SPOTIFLAC_DISCORD_SDK_DIR", BuildConfig.HAS_DISCORD_SDK)
        assumeTrue("This test must not publish to a signed-in account",
            instrumentation.targetContext.packageManager.getLaunchIntentForPackage("com.discord") == null)
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        try {
            instrumentation.runOnMainSync {
                assertEquals("discord_missing", DiscordPresenceBridge.configure(activity, true))
                assertEquals("disabled", DiscordPresenceBridge.configure(activity, false))
                System.loadLibrary("spotiflac_discord")
                Class.forName("com.discord.socialsdk.DiscordSocialSdkInit")
                    .getMethod("setEngineActivity", android.app.Activity::class.java)
                    .invoke(null, activity)
                DiscordNative.start(1549854098801692862L)
                DiscordNative.update("Track 🎵", "Lead & Guest", "Album", "", 1000, 2000)
                DiscordNative.clear()
                DiscordNative.stop()
            }
            repeat(20) {
                Thread.sleep(50)
                instrumentation.runOnMainSync { assertEquals("disabled", DiscordNative.poll()) }
            }
            instrumentation.runOnMainSync {
                DiscordNative.start(1549854098801692862L)
                assertEquals("ready", DiscordNative.poll())
                DiscordNative.stop()
                assertEquals("disabled", DiscordNative.poll())
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
