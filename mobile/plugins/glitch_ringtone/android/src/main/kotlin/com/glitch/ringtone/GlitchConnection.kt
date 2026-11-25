package com.glitch.ringtone

import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.O)
class GlitchConnection : Connection() {

    override fun onShowIncomingCallUi() {
        GlitchTelecom.notify("showIncomingUi")
    }

    override fun onAnswer() {
        GlitchTelecom.notify("answer")
    }

    override fun onReject() {
        closeWith(DisconnectCause.REJECTED)
        GlitchTelecom.notify("reject")
    }

    override fun onDisconnect() {
        closeWith(DisconnectCause.LOCAL)
        GlitchTelecom.notify("disconnect")
    }

    override fun onAbort() {
        closeWith(DisconnectCause.CANCELED)
        GlitchTelecom.notify("disconnect")
    }

    private var lastMuted = false

    override fun onCallAudioStateChanged(state: CallAudioState) {
        if (state.isMuted == lastMuted) return
        lastMuted = state.isMuted
        GlitchTelecom.notify(if (state.isMuted) "muted" else "unmuted")
    }

    fun closeWith(cause: Int) {
        GlitchTelecom.forget(this)
        try {
            setDisconnected(DisconnectCause(cause))
            destroy()
        } catch (e: Exception) {
        }
    }
}
