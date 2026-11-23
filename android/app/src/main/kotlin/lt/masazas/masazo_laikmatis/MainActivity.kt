package lt.masazas.masazo_laikmatis

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.*
import android.provider.Settings
import android.os.PowerManager
import android.net.Uri
import android.app.AlertDialog
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var recognizer: SpeechRecognizer? = null
    private var listening: MethodChannel.Result? = null
    private var notificationRequest: (() -> Unit)? = null
    private var microphoneRequest: (() -> Unit)? = null
    private var backgroundSuccess: (() -> Unit)? = null
    private var backgroundResult: MethodChannel.Result? = null
    private var voiceDeadline: Runnable? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val voice get() = VoiceOutput.get(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TimerStore.load(this)
        voice.ready { error -> if (error != null) TimerStore.error = error }
        if (TimerStore.timer.phase in listOf("running", "paused")) {
            startForegroundService(Intent(this, TimerService::class.java).setAction("restore"))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lt.masazas/timer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> result.success(TimerStore.snapshot())
                    "start" -> {
                        val id = call.argument<String>("id")
                        if (id !in Timeline.PRESETS) result.error("preset", "Nepasirinktas masažas.", null)
                        else if (TimerStore.timer.phase in listOf("running", "paused"))
                            result.error("active", "Pirmiausia sustabdykite veikiantį laikmatį.", null)
                        else voice.ready { error ->
                            if (error != null) result.error("voice", error, null)
                            else ensureNotifications { ensureBackground(result) {
                                try {
                                    startForegroundService(Intent(this, TimerService::class.java)
                                        .setAction("start").putExtra("id", id))
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error("service", "Nepavyko paleisti laikmačio: ${e.localizedMessage}", null)
                                }
                            } }
                        }
                    }
                    "pause", "resume", "stop" -> {
                        if (TimerStore.timer.phase in listOf("running", "paused")) {
                            startService(Intent(this, TimerService::class.java).setAction(call.method))
                        }
                        result.success(null)
                    }
                    "remaining" -> {
                        val timer = TimerStore.timer
                        val text = when (timer.phase) {
                            "idle" -> "Laikmatis nepradėtas."
                            "finished" -> "Masažas baigtas."
                            else -> minutePhrase((timer.remaining(android.os.SystemClock.elapsedRealtime()) + 59999) / 60000)
                        }
                        voice.ready { error ->
                            if (error != null) result.error("voice", error, null)
                            else { voice.speak(text); result.success(null) }
                        }
                    }
                    "speak" -> voice.ready { error ->
                        if (error != null) result.error("voice", error, null)
                        else { voice.speak(call.argument<String>("text") ?: ""); result.success(null) }
                    }
                    "voiceSettings" -> {
                        try { startActivity(Intent("com.android.settings.TTS_SETTINGS")); result.success(null) }
                        catch (_: Exception) { startActivity(Intent(Settings.ACTION_SETTINGS)); result.success(null) }
                    }
                    "listen" -> {
                        if (listening != null) result.error("busy", "Jau klausomasi komandos.", null)
                        else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            microphoneRequest = { beginListening(result) }
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 101)
                            listening = result
                        } else beginListening(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    private fun ensureNotifications(continuation: () -> Unit) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationRequest = continuation
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 102)
        } else continuation()
    }
    private fun ensureBackground(result: MethodChannel.Result, continuation: () -> Unit) {
        if (getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)) {
            continuation(); return
        }
        AlertDialog.Builder(this).setTitle("Pranešimai užrakintame telefone")
            .setMessage("Kad laikas būtų pranešamas kas minutę ir užrakinus telefoną, leiskite laikmačiui veikti be baterijos taupymo apribojimų. Tai gali padidinti baterijos naudojimą masažo metu.")
            .setPositiveButton("Leisti") { _, _ ->
                backgroundSuccess = continuation; backgroundResult = result
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")), 103)
                } catch (_: Exception) {
                    backgroundSuccess = null; backgroundResult = null
                    result.error("battery", "Telefono baterijos nustatymuose leiskite šiai programėlei veikti be apribojimų ir bandykite dar kartą.", null)
                }
            }
            .setNegativeButton("Atšaukti") { _, _ -> result.error("battery", "Laikmatis nepradėtas. Veikimui užrakintame telefone reikia leidimo veikti be baterijos apribojimų.", null) }
            .setOnCancelListener { result.error("battery", "Laikmatis nepradėtas.", null) }
            .show()
    }
    @Deprecated("Android activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 103) {
            val continuation = backgroundSuccess; val result = backgroundResult
            backgroundSuccess = null; backgroundResult = null
            if (getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)) continuation?.invoke()
            else result?.error("battery", "Laikmatis nepradėtas. Leiskite veikti be baterijos taupymo apribojimų ir bandykite dar kartą.", null)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 102) {
            // Notification denial does not prohibit an Android foreground service.
            notificationRequest?.invoke(); notificationRequest = null
        }
        if (requestCode == 101) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) microphoneRequest?.invoke()
            else { listening?.error("microphone", "Balso komandoms suteikite mikrofono leidimą telefono nustatymuose.", null); listening = null }
            microphoneRequest = null
        }
    }
    private fun beginListening(result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            listening = null
            result.error("unavailable", "Telefone nėra kalbos atpažinimo paslaugos. Naudokite mygtukus arba įdiekite kalbos paslaugą.", null)
            return
        }
        voice.stop()
        voice.mutedForRecognition = true
        recognizer?.destroy()
        listening = result
        recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val words = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
                val pending = clearListening(); pending?.success(words)
            }
            override fun onError(error: Int) {
                val message = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Komandos neišgirdau. Paspauskite „Kalbėti“ ir bandykite dar kartą."
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Nesuteiktas mikrofono leidimas."
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "Kalbos atpažinimo paslauga nepalaiko lietuvių kalbos."
                    else -> "Balso atpažinimas nepavyko. Patikrinkite interneto ryšį ir kalbos paslaugą."
                }
                val pending = clearListening(); pending?.error("recognition", message, null)
            }
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val timeout = Runnable {
            val pending = clearListening()
            recognizer?.cancel()
            pending?.error("timeout", "Komandos neišgirdau. Bandykite dar kartą.", null)
        }
        voiceDeadline = timeout
        handler.postDelayed(timeout, 15000)
        try {
            recognizer?.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "lt-LT")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            })
        } catch (_: Exception) {
            clearListening()?.error("recognition", "Nepavyko įjungti kalbos atpažinimo.", null)
        }
    }
    private fun clearListening(): MethodChannel.Result? {
        voice.mutedForRecognition = false
        voiceDeadline?.let { handler.removeCallbacks(it) }; voiceDeadline = null
        val pending = listening; listening = null
        return pending
    }
    override fun onStop() {
        if (listening != null && microphoneRequest == null) {
            clearListening()?.error("cancelled", "Balso klausymas sustabdytas išėjus iš programėlės.", null)
            recognizer?.cancel()
        }
        super.onStop()
    }
    override fun onDestroy() {
        clearListening()?.error("cancelled", "Balso klausymas sustabdytas.", null)
        recognizer?.destroy(); recognizer = null
        super.onDestroy()
    }
}
