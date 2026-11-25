package com.glitch.ringtone

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

object GlitchTelecom {

    private const val ACCOUNT_ID = "glitch_calls"

    // Поля закрытые, работа с ними — только через методы ниже, и каждый из них
    // @Synchronized. Так же сделано в CallRingtonePlayer: там synchronized снял
    // целый класс гонок, из-за которых мелодия оставалась звучать после конца
    // звонка. Здесь ровно та же болезнь, только вместо мелодии остаётся
    // «идущий разговор» в глазах системы.

    private var current: GlitchConnection? = null

    /**
     * НОМЕР ПОПЫТКИ — защита от соединения, созданного вдогонку.
     *
     * ПОЧЕМУ ОН НУЖЕН. reportIncoming/reportOutgoing только ПРОСЯТ систему
     * завести звонок. Само соединение она создаёт, когда сочтёт нужным, —
     * своим вызовом GlitchConnectionService, и между просьбой и созданием
     * проходит время. Звонок за это время успевает кончиться: собеседник
     * передумал, сервер ответил «занято», человек нажал отбой.
     *
     * Раньше в этом случае setEnded не находил соединения (его ещё не было) и
     * молча выходил, а созданное следом соединение оставалось жить вечно —
     * закрывать его было уже некому. Снаружи это выглядело так: телефон
     * «остался в звонке» после звонка, которого давно нет.
     *
     * Приём тот же, что у client_token исходящего звонка в call_provider.dart
     * и у _wanted в call_foreground_service.dart: у каждой попытки свой номер,
     * ожидается ровно последний, всё пришедшее с чужим номером — от попытки,
     * которую уже бросили.
     */
    private var attemptSeq = 0

    private var pendingAttempt = 0

    @Synchronized
    private fun beginAttempt(): Int {
        attemptSeq++
        if (attemptSeq == 0) attemptSeq = 1
        pendingAttempt = attemptSeq
        return attemptSeq
    }

    @Synchronized
    private fun cancelAttempt(attempt: Int) {
        if (attempt != 0 && attempt == pendingAttempt) pendingAttempt = 0
    }

    @Synchronized
    internal fun abandon(extras: Bundle?) {
        cancelAttempt(attemptFrom(extras))
    }

    /**
     * Принять только что созданное системой соединение как текущее.
     *
     * false означает «звонка уже нет»: соединение опоздало, и его надо закрыть
     * сразу — см. GlitchConnectionService.staleConnection.
     *
     * Прежнее соединение здесь не закрывается намеренно: к этому моменту его
     * уже не должно быть. Двух звонков разом у нас не бывает — приложение не
     * начинает новый, пока идёт текущий (проверки isBusy в startCall и
     * _onIncoming, call_provider.dart), а конец каждого проходит через
     * setEnded. Если этот инвариант когда-нибудь сломается, симптом будет
     * прежний — «телефон остался в звонке», и искать надо здесь.
     */
    @Synchronized
    internal fun adopt(connection: GlitchConnection, extras: Bundle?): Boolean {
        if (pendingAttempt == 0) return false
        val attempt = attemptFrom(extras)
        if (attempt != 0 && attempt != pendingAttempt) return false
        current = connection
        return true
    }

    @Synchronized
    internal fun forget(connection: GlitchConnection) {
        if (current !== connection) return
        current = null
        pendingAttempt = 0
    }

    @Synchronized
    private fun takeCurrent(): GlitchConnection? {
        // Попытку снимаем всегда, даже когда соединения ещё нет: этим и
        // закрывается гонка — созданное следом соединение уже никто не ждёт.
        pendingAttempt = 0
        val connection = current
        current = null
        return connection
    }


    @Volatile
    private var onEvent: ((String) -> Unit)? = null

    fun claimListener(listener: (String) -> Unit) {
        onEvent = listener
    }

    fun releaseListener(listener: (String) -> Unit) {
        if (onEvent === listener) onEvent = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    internal fun notify(event: String) {
        mainHandler.post { onEvent?.invoke(event) }
    }


    private fun handle(context: Context): PhoneAccountHandle =
        PhoneAccountHandle(
            ComponentName(context.packageName, GlitchConnectionService::class.java.name),
            ACCOUNT_ID,
        )

    fun register(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return false
            val account = PhoneAccount.builder(handle(context), "Glitch")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .addSupportedUriScheme(PhoneAccount.SCHEME_SIP)
                .build()
            telecom.registerPhoneAccount(account)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun addressOf(name: String): Uri =
        Uri.fromParts(PhoneAccount.SCHEME_SIP, "$name@glitch", null)

    fun reportIncoming(context: Context, callerName: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        var attempt = 0
        return try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return false
            attempt = beginAttempt()
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, addressOf(callerName))
                putString(EXTRA_CALLER_NAME, callerName)
                putInt(EXTRA_ATTEMPT, attempt)
            }
            telecom.addNewIncomingCall(handle(context), extras)
            true
        } catch (e: Exception) {
            cancelAttempt(attempt)
            false
        }
    }

    fun reportOutgoing(context: Context, calleeName: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        var attempt = 0
        return try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return false
            attempt = beginAttempt()
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
                putString(EXTRA_CALLER_NAME, calleeName)
                putInt(EXTRA_ATTEMPT, attempt)
            }
            telecom.placeCall(addressOf(calleeName), extras)
            true
        } catch (e: Exception) {
            cancelAttempt(attempt)
            false
        }
    }

    fun setActive() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            currentConnection()?.setActive()
        } catch (e: Exception) {
        }
    }

    /**
     * Переключить вывод звука: громкая связь или обычный разговорный динамик.
     *
     * ПОЧЕМУ ЭТО ОБЯЗАНО ИДТИ ЧЕРЕЗ ТЕЛЕФОНИЮ. Пока у нас есть живое соединение
     * телефонии, маршрутом звука распоряжается система, а не приложение:
     * обычный AudioManager.setSpeakerphoneOn (именно его зовёт flutter_webrtc)
     * она в этом состоянии игнорирует. Снаружи это выглядело как молча
     * неработающая кнопка «Динамик» — без ошибок, без записей в журнале,
     * найдено живым тестом 2026-09-06.
     *
     * ROUTE_WIRED_OR_EARPIECE, а НЕ ROUTE_EARPIECE, при выключении: если в
     * телефон воткнуты наушники, звук обязан идти в них, а не в динамик у уха.
     * Система сама выберет из этих двух то, что подключено.
     *
     * @return false — соединения телефонии нет (система его не приняла, или
     * звонок уже кончился). Тогда вызывающий обязан переключить вывод обычным
     * способом; здесь мы за него не решаем.
     */
    fun setSpeaker(on: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val connection = currentConnection() ?: return false
        return try {
            connection.setAudioRoute(
                if (on) CallAudioState.ROUTE_SPEAKER
                else CallAudioState.ROUTE_WIRED_OR_EARPIECE
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    @Synchronized
    private fun currentConnection(): GlitchConnection? = current

    fun setEnded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        takeCurrent()?.closeWith(DisconnectCause.LOCAL)
    }


    internal const val EXTRA_CALLER_NAME = "glitch_caller_name"

    private const val EXTRA_ATTEMPT = "glitch_call_attempt"

    private fun ownExtras(extras: Bundle?): Bundle? {
        val nested = extras?.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS)
        return if (nested?.containsKey(EXTRA_CALLER_NAME) == true) nested else extras
    }

    internal fun callerNameFrom(extras: Bundle?): String =
        ownExtras(extras)?.getString(EXTRA_CALLER_NAME) ?: "Glitch"

    private fun attemptFrom(extras: Bundle?): Int =
        ownExtras(extras)?.getInt(EXTRA_ATTEMPT, 0) ?: 0

    internal fun configure(connection: Connection, name: String, address: Uri?) {
        connection.setAddress(address, TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED)
        connection.setAudioModeIsVoip(true)
        connection.connectionCapabilities = Connection.CAPABILITY_MUTE
    }
}
