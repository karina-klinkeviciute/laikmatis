package lt.masazas.masazo_laikmatis

import android.content.Context
import android.media.*
import android.os.PowerManager
import org.json.JSONObject

/** Bundled Lithuanian recordings work offline, without an installed TTS engine. */
class VoiceOutput(private val context: Context) {
    var mutedForRecognition = false
    private val audio = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        .setAudioAttributes(attributes).setOnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stop()
        }.build()
    private val clips: JSONObject? = try {
        context.assets.open("flutter_assets/assets/voice/phrases.json").bufferedReader().use { JSONObject(it.readText().removePrefix("\uFEFF")) }
    } catch (_: Exception) { null }
    private var player: MediaPlayer? = null
    private var onFinished: (() -> Unit)? = null

    fun ready(callback: (String?) -> Unit) {
        callback(if (clips == null) "Nepavyko atverti lietuviškų pranešimų. Įdiekite programėlę iš naujo." else null)
    }
    fun speak(text: String, done: (() -> Unit)? = null) {
        if (mutedForRecognition) { done?.invoke(); return }
        stop()
        val file = clips?.optString(text, "") ?: ""
        if (file.isEmpty()) {
            TimerStore.error = "Nerastas lietuviškas pranešimas."
            done?.invoke(); return
        }
        if (audio.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            TimerStore.error = "Garsas šiuo metu nepasiekiamas. Patikrinkite, ar nevyksta skambutis."
            done?.invoke(); return
        }
        onFinished = done
        try {
            val next = MediaPlayer()
            player = next
            next.setAudioAttributes(attributes)
            next.setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
            context.assets.openFd("flutter_assets/assets/voice/$file").use {
                next.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            next.setOnCompletionListener { finish() }
            next.setOnErrorListener { _, _, _ ->
                TimerStore.error = "Nepavyko paleisti garsinio pranešimo."; finish(); true
            }
            next.prepare(); next.start()
        } catch (_: Exception) {
            TimerStore.error = "Nepavyko paleisti garsinio pranešimo."; finish()
        }
    }
    private fun finish() {
        val callback = onFinished; onFinished = null
        stop(); callback?.invoke()
    }
    fun stop() {
        onFinished = null
        player?.release(); player = null
        audio.abandonAudioFocusRequest(focus)
    }
    companion object {
        private var shared: VoiceOutput? = null
        fun get(context: Context): VoiceOutput = shared ?: VoiceOutput(context.applicationContext).also { shared = it }
    }
}
