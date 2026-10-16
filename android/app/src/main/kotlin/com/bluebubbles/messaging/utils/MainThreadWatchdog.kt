package com.bluebubbles.messaging.utils

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean

/// Diagnostic for "OpenBubbles isn't responding" (2026-10-16). Records only;
/// changes no behaviour.
///
/// On Flutter 3.44 every engine's Dart isolate runs on Android's main thread
/// (the DisableMergedPlatformUIThread manifest flag is ignored inside
/// <activity> and refused inside <application>), so a stall can be Dart or
/// Kotlin. Two records go to native.log under this tag:
///  - "main thread blocked": a background thread posts to the main looper every
///    half second; when a post waits 1.5 s or more, the main thread's Java stack
///    is sampled (at 1.5, 3.5 and 5.5 s) and logged with the total wait once it
///    runs. A stack ending in MessageQueue.nativePollOnce means Dart (or other
///    native work) held the thread; Kotlin frames name the Kotlin code. The Dart
///    log lines just before the record's timestamp show what Dart was doing.
///  - "Android recorded ANR": at start-up, ANR exits Android kept for this app
///    (only when the process was closed or killed, not when "Wait" was chosen),
///    with the main thread section of Android's trace.
object MainThreadWatchdog {
    private const val TAG = "MainThreadWatchdog"
    private const val TICK_MS = 500L
    private const val REPORT_MS = 1500L
    private const val SAMPLE_EVERY_MS = 2000L
    private const val MAX_SAMPLES = 3
    private const val PREFS = "main_thread_watchdog"
    private const val LAST_ANR_KEY = "lastAnrTimestamp"

    private val started = AtomicBoolean(false)

    fun start(context: Context) {
        if (!started.compareAndSet(false, true)) return
        val app = context.applicationContext
        Thread({ logRecordedAnrs(app) }, "MainThreadWatchdog-exits").apply { isDaemon = true }.start()
        Thread({ watch(app) }, "MainThreadWatchdog").apply { isDaemon = true }.start()
    }

    private fun watch(app: Context) {
        val main = Handler(Looper.getMainLooper())
        while (true) {
            try {
                val ran = AtomicBoolean(false)
                val posted = SystemClock.uptimeMillis()
                main.post { ran.set(true) }
                val samples = ArrayList<String>()
                var nextSample = REPORT_MS
                while (!ran.get()) {
                    Thread.sleep(50)
                    val waited = SystemClock.uptimeMillis() - posted
                    if (waited >= nextSample && samples.size < MAX_SAMPLES) {
                        samples.add("at ${waited} ms:\n${mainStack()}")
                        nextSample += SAMPLE_EVERY_MS
                    }
                }
                val waited = SystemClock.uptimeMillis() - posted
                if (waited >= REPORT_MS) {
                    PersistentLog.w(app, TAG, "main thread blocked ${waited} ms (ended now)\n" + samples.joinToString("\n"))
                }
                Thread.sleep(TICK_MS)
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                PersistentLog.w(app, TAG, "watchdog error", e)
                Thread.sleep(TICK_MS)
            }
        }
    }

    private fun mainStack(): String =
        Looper.getMainLooper().thread.stackTrace.take(25).joinToString("\n") { "    $it" }

    private fun logRecordedAnrs(app: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val am = app.getSystemService(ActivityManager::class.java) ?: return
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val last = prefs.getLong(LAST_ANR_KEY, 0L)
            var newest = last
            for (info in am.getHistoricalProcessExitReasons(null, 0, 20)) {
                if (info.reason != ApplicationExitInfo.REASON_ANR || info.timestamp <= last) continue
                newest = maxOf(newest, info.timestamp)
                val trace = try {
                    info.traceInputStream?.bufferedReader()?.use { mainThreadSection(it.readLines()) } ?: "(no trace)"
                } catch (e: Exception) {
                    "(trace unreadable: $e)"
                }
                PersistentLog.w(app, TAG, "Android recorded ANR at ${Instant.ofEpochMilli(info.timestamp)} " +
                        "(${info.processName}): ${info.description}\n$trace")
            }
            if (newest != last) prefs.edit().putLong(LAST_ANR_KEY, newest).apply()
        } catch (e: Exception) {
            PersistentLog.w(app, TAG, "could not read exit reasons", e)
        }
    }

    /// The "main" thread block of an ANR trace, capped at 60 lines.
    private fun mainThreadSection(lines: List<String>): String {
        val start = lines.indexOfFirst { it.startsWith("\"main\"") }
        if (start < 0) return lines.take(40).joinToString("\n")
        val out = ArrayList<String>()
        for (i in start until lines.size) {
            if (i > start && lines[i].isBlank()) break
            out.add(lines[i])
            if (out.size >= 60) break
        }
        return out.joinToString("\n")
    }
}
