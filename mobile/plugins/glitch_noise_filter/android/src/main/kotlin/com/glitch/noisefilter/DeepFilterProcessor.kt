package com.glitch.noisefilter

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.rikorose.deepfilternet.NativeDeepFilterNet
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal class DeepFilterProcessor(
    context: Context,
    attenuationDb: Float,
) : AudioProcessingAdapter.ExternalAudioFrameProcessing {

    private val net = NativeDeepFilterNet(context, attenuationDb)

    @Volatile
    private var ready = false

    private var released = false

    private val frame: ByteBuffer =
        ByteBuffer.allocateDirect(FRAME_SAMPLES * 2).order(ByteOrder.LITTLE_ENDIAN)

    private var rateWarned = false

    init {
        net.onModelLoaded {
            if (released) {
                net.release()
            } else if (net.frameLength.toInt() != FRAME_SAMPLES * 2) {
                Log.e(TAG, "unexpected frame length ${net.frameLength}, filter stays off")
            } else {
                ready = true
            }
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {}

    override fun reset(newRate: Int) {}

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer?) {
        if (!ready || buffer == null) return
        if (numFrames != FRAME_SAMPLES) {
            if (!rateWarned) {
                rateWarned = true
                Log.w(TAG, "audio is processed at ${numFrames * 100} Hz, filter needs 48000")
            }
            return
        }
        val samples = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
        if (samples.limit() < FRAME_SAMPLES) return
        for (i in 0 until FRAME_SAMPLES) {
            val value = samples.get(i).coerceIn(-32768f, 32767f)
            frame.putShort(i * 2, value.toInt().toShort())
        }
        frame.rewind()
        net.processFrame(frame)
        for (i in 0 until FRAME_SAMPLES) {
            samples.put(i, frame.getShort(i * 2).toFloat())
        }
    }

    fun release() {
        ready = false
        released = true
        net.release()
    }

    private companion object {
        const val TAG = "GlitchNoiseFilter"

        const val FRAME_SAMPLES = 480
    }
}
