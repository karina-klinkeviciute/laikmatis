package lt.masazas.masazo_laikmatis

/** Monotonic clock only: changing the phone's wall clock cannot change a massage. */
class Timeline {
    var phase = "idle"
    var id = "left_one"
    var duration = 1_800_000L
    var interval = 60_000L
    var deadline = 0L
    var pausedRemaining = duration
    var announced = 0L

    fun start(preset: String, now: Long) {
        require(preset in PRESETS)
        id = preset
        duration = if (preset.startsWith("left")) 1_800_000L else 3_600_000L
        interval = if (preset.endsWith("one")) 60_000L else 300_000L
        deadline = now + duration
        pausedRemaining = duration
        announced = 0
        phase = "running"
    }
    fun remaining(now: Long): Long = when (phase) {
        "running" -> (deadline - now).coerceIn(0, duration)
        "finished" -> 0
        else -> pausedRemaining
    }
    fun pause(now: Long) {
        if (phase != "running") return
        pausedRemaining = remaining(now)
        phase = if (pausedRemaining == 0L) "finished" else "paused"
    }
    fun resume(now: Long) {
        if (phase != "paused") return
        deadline = now + pausedRemaining
        phase = "running"
    }
    fun stop() { phase = "idle"; pausedRemaining = duration; announced = 0 }
    /** Returns only the latest due boundary: no burst of stale announcements after a delay. */
    fun tick(now: Long): Long? {
        if (phase != "running") return null
        val left = remaining(now)
        if (left == 0L) { phase = "finished"; return 0 }
        val boundary = (duration - left) / interval
        if (boundary <= announced) return null
        announced = boundary
        return left
    }
    companion object { val PRESETS = setOf("left_one", "left_two", "right_one", "right_two") }
}

fun minutePhrase(minutes: Long): String {
    val noun = when {
        minutes % 100 in 11..19 || minutes % 10 == 0L -> "minučių"
        minutes % 10 == 1L -> "minutė"
        else -> "minutės"
    }
    return "Liko $minutes $noun"
}

fun presetLabel(id: String): String {
    val side = if (id.startsWith("left")) "Kairė" else "Dešinė"
    val name = if (id.endsWith("one")) "masažas vienas" else "masažas du"
    return "$side pusė, $name"
}
