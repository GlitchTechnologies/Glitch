package com.glitch.noisefilter

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

internal class VoiceGateProcessor : AudioProcessingAdapter.ExternalAudioFrameProcessing {

    @Volatile
    private var auto = true

    @Volatile
    private var thresholdDb = -60f

    @Volatile
    var levelDb = SILENCE_DB
        private set

    private var gain = 1f
    private var holdLeft = 0
    private val parts = ArrayDeque<Float>()
    private var partMin = 0f
    private var partLeft = 0
    private var peak = SILENCE_DB
    private var reportLeft = 0

    fun configure(auto: Boolean, thresholdDb: Float) {
        this.auto = auto
        this.thresholdDb = thresholdDb
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {}

    override fun reset(newRate: Int) {}

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer?) {
        if (buffer == null || numFrames <= 0) return
        val samples = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val n = min(numFrames, samples.limit())
        if (n <= 0) return
        val rate = numFrames * 100

        var sum = 0.0
        for (i in 0 until n) {
            val x = samples.get(i) / FULL_SCALE
            sum += x * x
        }
        val rms = sqrt(sum / n)
        val db = if (rms > 0) (20 * log10(rms)).toFloat().coerceIn(SILENCE_DB, 0f) else SILENCE_DB

        if (db > peak) peak = db
        reportLeft -= n
        if (reportLeft <= 0) {
            levelDb = peak
            peak = SILENCE_DB
            reportLeft = rate * REPORT_MS / 1000
        }

        val floor = floorDb(db, n, rate)
        val threshold = if (auto) {
            (floor + AUTO_MARGIN_DB).coerceIn(AUTO_MIN_DB, AUTO_MAX_DB)
        } else {
            thresholdDb
        }
        holdLeft = if (db >= threshold) rate * HOLD_MS / 1000 else max(0, holdLeft - n)
        val target = if (holdLeft > 0) 1f else 0f

        val openStep = 1f / (rate * OPEN_MS / 1000f)
        val closeStep = 1f / (rate * CLOSE_MS / 1000f)
        for (i in 0 until n) {
            if (gain < target) {
                gain = min(target, gain + openStep)
            } else if (gain > target) {
                gain = max(target, gain - closeStep)
            }
            if (gain < 1f) samples.put(i, samples.get(i) * gain)
        }
    }

    private fun floorDb(db: Float, n: Int, rate: Int): Float {
        if (partLeft <= 0) {
            partMin = db
            partLeft = (rate.toLong() * FLOOR_WINDOW_MS / 1000 / FLOOR_PARTS).toInt()
        } else if (db < partMin) {
            partMin = db
        }
        partLeft -= n
        if (partLeft <= 0) {
            parts.addLast(partMin)
            if (parts.size > FLOOR_PARTS) parts.removeFirst()
        }
        var floor = partMin
        for (part in parts) if (part < floor) floor = part
        return floor
    }

    private companion object {
        const val FULL_SCALE = 32768.0
        const val SILENCE_DB = -100f
        const val HOLD_MS = 300
        const val AUTO_MARGIN_DB = 15f
        const val AUTO_MIN_DB = -70f
        const val AUTO_MAX_DB = -30f
        const val FLOOR_WINDOW_MS = 4000
        const val FLOOR_PARTS = 8
        const val REPORT_MS = 50
        const val OPEN_MS = 5
        const val CLOSE_MS = 50
    }
}
