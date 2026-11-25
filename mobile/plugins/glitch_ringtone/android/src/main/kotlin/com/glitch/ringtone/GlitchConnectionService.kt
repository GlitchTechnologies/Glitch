package com.glitch.ringtone

import android.os.Build
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.O)
class GlitchConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        val connection = GlitchConnection()
        if (!GlitchTelecom.adopt(connection, request?.extras)) return staleConnection()
        GlitchTelecom.configure(
            connection,
            GlitchTelecom.callerNameFrom(request?.extras),
            request?.address,
        )
        connection.setRinging()
        return connection
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        val connection = GlitchConnection()
        if (!GlitchTelecom.adopt(connection, request?.extras)) return staleConnection()
        GlitchTelecom.configure(
            connection,
            GlitchTelecom.callerNameFrom(request?.extras),
            request?.address,
        )
        connection.setDialing()
        return connection
    }

    private fun staleConnection(): Connection =
        Connection.createFailedConnection(DisconnectCause(DisconnectCause.CANCELED))

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ) {
        GlitchTelecom.abandon(request?.extras)
        GlitchTelecom.notify("rejectedBySystem")
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ) {
        GlitchTelecom.abandon(request?.extras)
        GlitchTelecom.notify("rejectedBySystem")
    }
}
