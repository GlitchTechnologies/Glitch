package com.glitch.ringtone

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer

object VoiceCuePlayer {

    private var player: MediaPlayer? = null

    @Synchronized
    fun play(context: Context, resName: String) {
        val resId = context.resources.getIdentifier(resName, "raw", context.packageName)
        if (resId == 0) return  // файла нет — просто без звука
        release()
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
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            // Доиграл или сломался — освободить: одноразовый звук не висит.
            mp.setOnCompletionListener { finished(it) }
            mp.setOnErrorListener { p, _, _ ->
                finished(p)
                true
            }
            mp.prepare()
            mp.start()
            player = mp
        } catch (e: Exception) {
            try {
                created?.release()
            } catch (ignored: Exception) {
            }
        }
    }

    @Synchronized
    private fun finished(mp: MediaPlayer) {
        if (player === mp) player = null
        try {
            mp.release()
        } catch (e: Exception) {
        }
    }

    @Synchronized
    private fun release() {
        val mp = player ?: return
        player = null
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
