package com.glitch.ringtone

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class GlitchRingtonePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    private val telecomSender: (String) -> Unit = { event ->
        try {
            channel.invokeMethod("telecom", event)
        } catch (e: Exception) {
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "glitch/ringtone")
        channel.setMethodCallHandler(this)

    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        GlitchTelecom.releaseListener(telecomSender)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "playIncoming" -> {
                val callId = callIdOf(call)
                if (callId != null) KnownCalls.claim(callId)
                val silent = call.argument<Boolean>("silent") == true
                CallRingtonePlayer.play(appContext, "call_ringtone", ringtone = true, callId = callId, silent = silent)
                result.success(null)
            }
            "claimIncoming" -> {
                val callId = callIdOf(call)
                result.success(
                    when {
                        callId == null -> "first"
                        KnownCalls.claim(callId) -> "first"
                        CallRingtonePlayer.isRinging(callId) -> "ringing"
                        else -> "handled"
                    }
                )
            }
            "finishRinging" -> {
                val callId = callIdOf(call)
                result.success(callId == null || CallRingtonePlayer.finishRinging(callId))
            }
            "playOutgoing" -> {
                CallRingtonePlayer.play(appContext, "call_ringback", ringtone = false)
                result.success(null)
            }
            "stop" -> {
                CallRingtonePlayer.stop()
                result.success(null)
            }
            "playCue" -> {
                val name = call.argument<String>("name")
                if (name != null) VoiceCuePlayer.play(appContext, name)
                result.success(null)
            }

            // Системные настройки, от которых зависит доставка звонка.
            // Почему они здесь, а не в permission_handler: обычными
            // разрешениями Android они не являются — см. CallSystemSettings.
            "isIgnoringBatteryOptimizations" ->
                result.success(CallSystemSettings.isIgnoringBatteryOptimizations(appContext))
            "requestIgnoreBatteryOptimizations" -> {
                CallSystemSettings.requestIgnoreBatteryOptimizations(appContext)
                result.success(null)
            }
            "hasFullScreenSetting" ->
                result.success(CallSystemSettings.hasFullScreenSetting())
            "canUseFullScreenIntent" ->
                result.success(CallSystemSettings.canUseFullScreenIntent(appContext))
            "openFullScreenIntentSettings" -> {
                CallSystemSettings.openFullScreenIntentSettings(appContext)
                result.success(null)
            }
            "hasLockScreenPermissionScreen" ->
                result.success(CallSystemSettings.hasLockScreenPermissionScreen(appContext))
            "openLockScreenPermissionSettings" -> {
                CallSystemSettings.openLockScreenPermissionSettings(appContext)
                result.success(null)
            }
            "hasAutostartSettings" ->
                result.success(CallSystemSettings.hasAutostartSettings(appContext))
            "openAutostartSettings" -> {
                CallSystemSettings.openAutostartSettings(appContext)
                result.success(null)
            }

            "telecomRegister" -> result.success(GlitchTelecom.register(appContext))
            "telecomListen" -> {
                GlitchTelecom.claimListener(telecomSender)
                result.success(null)
            }
            "telecomIncoming" ->
                result.success(GlitchTelecom.reportIncoming(appContext, call.arguments as? String ?: "Glitch"))
            "telecomOutgoing" ->
                result.success(GlitchTelecom.reportOutgoing(appContext, call.arguments as? String ?: "Glitch"))
            "telecomActive" -> {
                GlitchTelecom.setActive()
                result.success(null)
            }
            "telecomEnded" -> {
                GlitchTelecom.setEnded()
                result.success(null)
            }
            "telecomSpeaker" ->
                result.success(GlitchTelecom.setSpeaker(call.arguments as? Boolean ?: false))

            else -> result.notImplemented()
        }
    }

    private fun callIdOf(call: MethodCall): Long? =
        (call.argument<Any>("callId") as? Number)?.toLong()
}
