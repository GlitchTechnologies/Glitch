package com.glitch.noisefilter

import android.content.Context
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class GlitchNoiseFilterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var engine: FlutterEngine? = null

    private var noise: DeepFilterProcessor? = null
    private var gate: VoiceGateProcessor? = null

    private var attachedTo: AudioProcessingAdapter? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        @Suppress("DEPRECATION")
        engine = binding.flutterEngine
        channel = MethodChannel(binding.binaryMessenger, "glitch/noise_filter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopNoise()
        clearGate()
        channel.setMethodCallHandler(null)
        engine = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val db = call.argument<Number>("attenuationDb")?.toFloat()
                if (db == null) {
                    result.error("INVALID_ARGUMENT", "attenuationDb is required", null)
                    return
                }
                // Throwable, а не Exception: нет библиотеки под процессор
                // устройства — это UnsatisfiedLinkError, и он тоже обязан стать
                // ответом «недоступно», а не падением приложения.
                try {
                    startNoise(db)
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("NOISE_FILTER", t.toString(), null)
                }
            }
            "stop" -> {
                stopNoise()
                result.success(null)
            }
            "setGate" -> {
                val auto = call.argument<Boolean>("auto")
                val db = call.argument<Number>("thresholdDb")?.toFloat()
                if (auto == null || db == null) {
                    result.error("INVALID_ARGUMENT", "auto and thresholdDb are required", null)
                    return
                }
                try {
                    setGate(auto, db)
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("VOICE_GATE", t.toString(), null)
                }
            }
            "clearGate" -> {
                clearGate()
                result.success(null)
            }
            "level" -> result.success(gate?.levelDb?.toDouble())
            else -> result.notImplemented()
        }
    }

    private fun adapter(): AudioProcessingAdapter {
        val webrtc = engine?.plugins?.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
            ?: throw IllegalStateException("flutter_webrtc is not attached")
        return webrtc.audioProcessingController?.capturePostProcessing
            ?: throw IllegalStateException("WebRTC audio is not initialized")
    }

    private fun startNoise(attenuationDb: Float) {
        val adapter = adapter()
        if (noise != null && attachedTo === adapter) return
        if (noise == null) noise = DeepFilterProcessor(appContext, attenuationDb)
        relink(adapter)
    }

    private fun stopNoise() {
        val p = noise ?: return
        noise = null
        attachedTo?.removeProcessor(p)
        if (gate == null) attachedTo = null
        p.release()
    }

    private fun setGate(auto: Boolean, thresholdDb: Float) {
        val adapter = adapter()
        val current = gate
        if (current != null && attachedTo === adapter) {
            current.configure(auto, thresholdDb)
            return
        }
        gate = (current ?: VoiceGateProcessor()).also { it.configure(auto, thresholdDb) }
        relink(adapter)
    }

    private fun clearGate() {
        val g = gate ?: return
        gate = null
        attachedTo?.removeProcessor(g)
        if (noise == null) attachedTo = null
    }

    private fun relink(adapter: AudioProcessingAdapter) {
        val steps = listOfNotNull(noise, gate)
        for (step in steps) attachedTo?.removeProcessor(step)
        if (attachedTo !== adapter) for (step in steps) adapter.removeProcessor(step)
        for (step in steps) adapter.addProcessor(step)
        attachedTo = adapter
    }
}
