package lt.masazas.masazo_laikmatis

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

object TimerStore {
    val timer = Timeline()
    var error: String? = null
    private var loaded = false
    fun load(context: Context) {
        if (loaded) return
        loaded = true
        val prefs = context.getSharedPreferences("timer", Context.MODE_PRIVATE)
        val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
        timer.id = prefs.getString("id", "left_one") ?: "left_one"
        if (timer.id !in Timeline.PRESETS) timer.id = "left_one"
        timer.duration = if (timer.id.startsWith("left")) 1_800_000L else 3_600_000L
        timer.interval = if (timer.id.endsWith("one")) 60_000L else 300_000L
        timer.phase = prefs.getString("phase", "idle") ?: "idle"
        timer.deadline = prefs.getLong("deadline", 0)
        timer.pausedRemaining = prefs.getLong("paused", timer.duration)
        timer.announced = prefs.getLong("announced", 0)
        if (prefs.getInt("boot", boot) != boot) {
            if (timer.phase == "running") error = "Telefonas buvo paleistas iš naujo. Pradėkite naują masažą."
            timer.stop()
        }
        // A timer whose service was killed is completed on restoration, never silently restarted.
        if (timer.phase == "running" && timer.remaining(SystemClock.elapsedRealtime()) == 0L) {
            timer.phase = "finished"
        }
    }
    fun save(context: Context) {
        context.getSharedPreferences("timer", Context.MODE_PRIVATE).edit()
            .putString("id", timer.id).putString("phase", timer.phase)
            .putLong("deadline", timer.deadline).putLong("paused", timer.pausedRemaining)
            .putLong("announced", timer.announced)
            .putInt("boot", Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1))
            .apply()
    }
    fun snapshot(): Map<String, Any?> = mapOf(
        "phase" to timer.phase, "id" to timer.id,
        "remainingMs" to timer.remaining(SystemClock.elapsedRealtime()), "error" to error
    )
}
