package lt.masazas.masazo_laikmatis

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.*

class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val timer get() = TimerStore.timer
    private lateinit var voice: VoiceOutput
    private var wakeLock: PowerManager.WakeLock? = null
    private var chime: MediaPlayer? = null
    private var ending = false
    private val ticker = object : Runnable {
        override fun run() {
            if (timer.phase != "running") return
            val announcement = timer.tick(SystemClock.elapsedRealtime())
            if (announcement != null) {
                TimerStore.save(this@TimerService)
                if (announcement == 0L) { finishMassage(); return }
                voice.speak(minutePhrase((announcement + 59999) / 60000))
            }
            if ((timer.remaining(SystemClock.elapsedRealtime()) / 1000) % 10L == 0L) updateNotification()
            handler.postDelayed(this, 500)
        }
    }
    override fun onCreate() {
        super.onCreate()
        TimerStore.load(this)
        voice = VoiceOutput.get(this)
        val channel = NotificationChannel("massage", "Masažo laikmatis", NotificationManager.IMPORTANCE_LOW)
        channel.setSound(null, null)
        channel.description = "Veikiantis masažo laikmatis ir jo valdymas"
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        if (Build.VERSION.SDK_INT >= 29) startForeground(11, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(11, notification())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "restore"
        when (action) {
            "start" -> {
                val id = intent?.getStringExtra("id") ?: return START_NOT_STICKY
                if (id !in Timeline.PRESETS || timer.phase in listOf("running", "paused")) return START_STICKY
                ending = false
                chime?.release(); chime = null
                TimerStore.error = null
                timer.start(id, SystemClock.elapsedRealtime())
                voice.speak("${presetLabel(id)}. ${timer.duration / 60000} minučių. " +
                    if (timer.interval == 60000L) "Pranešimai kas minutę. Pradėta." else "Pranešimai kas penkias minutes. Pradėta.")
            }
            "pause" -> {
                if (timer.phase != "running") return START_STICKY
                if (timer.remaining(SystemClock.elapsedRealtime()) == 0L) {
                    timer.tick(SystemClock.elapsedRealtime()); finishMassage(); return START_STICKY
                }
                timer.pause(SystemClock.elapsedRealtime()); voice.speak("Laikmatis pristabdytas.")
            }
            "resume" -> { timer.resume(SystemClock.elapsedRealtime()); voice.speak("Laikmatis tęsiamas.") }
            "stop" -> {
                voice.stop(); chime?.release(); chime = null; ending = false
                timer.stop(); TimerStore.save(this)
                voice.speak("Laikmatis sustabdytas.")
                stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY
            }
            "restore" -> if (timer.phase !in listOf("running", "paused")) {
                stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY
            }
        }
        TimerStore.save(this)
        handler.removeCallbacks(ticker)
        if (timer.phase == "running") {
            acquireLock(); handler.post(ticker)
        } else releaseLock()
        updateNotification()
        return START_STICKY
    }
    private fun acquireLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "masazas:countdown").apply {
                setReferenceCounted(false)
                acquire(3_660_000L)
            }
    }
    private fun releaseLock() { if (wakeLock?.isHeld == true) wakeLock?.release(); wakeLock = null }
    private fun finishMassage() {
        if (ending) return
        ending = true
        TimerStore.save(this)
        voice.stop()
        updateNotification()
        // A bundled, generated three-note melody plays once, before the final spoken message.
        chime = MediaPlayer.create(this, R.raw.end_chime)?.apply {
            setWakeMode(this@TimerService, PowerManager.PARTIAL_WAKE_LOCK)
            setOnCompletionListener {
                it.release(); chime = null
                voice.speak("Masažas baigtas.") { finishService() }
            }
            setOnErrorListener { player, _, _ ->
                player.release(); chime = null
                voice.speak("Masažas baigtas.") { finishService() }; true
            }
            start()
        }
        if (chime == null) voice.speak("Masažas baigtas.") { finishService() }
        // A broken external TTS engine must not retain the service or wake lock indefinitely.
        handler.postDelayed({ if (ending) finishService() }, 20000)
    }
    private fun finishService() {
        ending = false
        releaseLock()
        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }
    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val left = (timer.remaining(SystemClock.elapsedRealtime()) + 999) / 1000
        val value = "%02d:%02d".format(left / 60, left % 60)
        val text = when (timer.phase) {
            "paused" -> "Pristabdyta · $value"
            "finished" -> "Masažas baigtas"
            else -> "Liko $value"
        }
        val builder = Notification.Builder(this, "massage")
            .setSmallIcon(R.drawable.ic_timer).setContentTitle(presetLabel(timer.id))
            .setContentText(text).setContentIntent(open).setOnlyAlertOnce(true)
            .setOngoing(timer.phase in listOf("running", "paused"))
            .setVisibility(Notification.VISIBILITY_PUBLIC).setCategory(Notification.CATEGORY_STOPWATCH)
        if (timer.phase in listOf("running", "paused")) {
            val pause = timer.phase == "running"
            builder.addAction(Notification.Action.Builder(null,
                if (pause) "Pristabdyti" else "Tęsti", action(if (pause) "pause" else "resume", 1)).build())
            builder.addAction(Notification.Action.Builder(null, "Sustabdyti", action("stop", 2)).build())
        }
        return builder.build()
    }
    private fun action(name: String, code: Int) = PendingIntent.getService(this, code,
        Intent(this, TimerService::class.java).setAction(name), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun updateNotification() = getSystemService(NotificationManager::class.java).notify(11, notification())
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        releaseLock(); chime?.release(); chime = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
