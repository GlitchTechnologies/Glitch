package com.glitch.ringtone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

object CallRingtonePlayer {

    private var player: MediaPlayer? = null

    private var currentRes: Int = 0

    private var ringingCallId: Long? = null

    private const val MAX_RING_MILLIS = 50_000L

    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stop() }

    @Synchronized
    fun play(context: Context, resName: String, ringtone: Boolean, callId: Long? = null, silent: Boolean = false) {
        val resId = context.resources.getIdentifier(resName, "raw", context.packageName)
        if (resId == 0) return  // файла нет — звонок пойдёт молча, но пойдёт
        if (currentRes == resId && player != null) {
            ringingCallId = if (ringtone) callId else null
            return
        }
        stop()
        ringingCallId = if (ringtone) callId else null

        if (ringtone) {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            when (audio.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> {
                    armAutoStop()
                    return
                }
                AudioManager.RINGER_MODE_VIBRATE -> {
                    startVibration(context)
                    armAutoStop()
                    return
                }
                // Обычный режим: мелодия, а вибрация — если человек её просил
                // в системных настройках («вибрация при звонке»).
                else -> if (vibrateWhenRinging(context)) startVibration(context)
            }
            if (silent) {
                armAutoStop()
                return
            }
        }

        val usage = if (ringtone) {
            AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        } else {
            AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING
        }

        // Отдельная ссылка ДЛЯ УБОРКИ: если что-то упадёт на полпути (чаще всего
        // на prepare), плеер надо освободить руками — сам он этого не сделает, а
        // в поле его ещё нет, и stop() до него не дотянется. Держим её отдельно
        // от рабочей `mp`, потому что к nullable-переменной внутри лямбды ниже
        // обратиться было бы нельзя.
        var created: MediaPlayer? = null
        try {
            val descriptor = context.resources.openRawResourceFd(resId) ?: return
            val mp = MediaPlayer()
            created = mp
            descriptor.use {
                mp.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(usage)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.isLooping = true
            mp.setOnErrorListener { _, _, _ ->
                stop()
                true
            }
            mp.prepare()
            mp.start()
            player = mp
            currentRes = resId
            armAutoStop()
        } catch (e: Exception) {
            try {
                created?.release()
            } catch (ignored: Exception) {
            }
            stop()
            if (ringtone) {
                ringingCallId = callId
                armAutoStop()
            }
        }
    }

    private fun armAutoStop() {
        handler.removeCallbacks(autoStop)
        handler.postDelayed(autoStop, MAX_RING_MILLIS)
    }

    @Synchronized
    fun isRinging(callId: Long): Boolean = ringingCallId == callId

    @Synchronized
    fun finishRinging(callId: Long): Boolean {
        val ringing = ringingCallId ?: return true
        if (ringing != callId) return false
        stop()
        return true
    }


    private val VIBRATION_PATTERN = longArrayOf(0, 800, 1000)

    private var vibrator: Vibrator? = null

    private fun vibrateWhenRinging(context: Context): Boolean = try {
        Settings.System.getInt(context.contentResolver, "vibrate_when_ringing", 0) == 1
    } catch (e: Exception) {
        false
    }

    private fun startVibration(context: Context) {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                        as? VibratorManager ?: return
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
            }
            if (!vib.hasVibrator()) return
            vibrator = vib

            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createWaveform(VIBRATION_PATTERN, 0), attributes)
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(VIBRATION_PATTERN, 0, attributes)
            }
        } catch (e: Exception) {
            vibrator = null
        }
    }

    private fun stopVibration() {
        val vib = vibrator ?: return
        vibrator = null
        try {
            vib.cancel()
        } catch (e: Exception) {
        }
    }

    @Synchronized
    fun stop() {
        stopVibration()
        handler.removeCallbacks(autoStop)
        ringingCallId = null
        val mp = player ?: run {
            currentRes = 0
            return
        }
        player = null
        currentRes = 0
        try {
            if (mp.isPlaying) mp.stop()
        } catch (e: Exception) {
        }
        try {
            mp.release()
        } catch (e: Exception) {
        }
    }
}
