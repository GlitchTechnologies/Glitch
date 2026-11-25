package com.glitch.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "glitch/app_control"

    override fun onCreate(savedInstanceState: Bundle?) {
        val launchIntent = intent
        if (launchIntent != null &&
            (launchIntent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        ) {
            launchIntent.action = Intent.ACTION_MAIN
            launchIntent.data = null
            launchIntent.removeExtra(Intent.EXTRA_STREAM)
            launchIntent.removeExtra(Intent.EXTRA_TEXT)
            launchIntent.removeExtra(Intent.EXTRA_SUBJECT)
        }
        super.onCreate(savedInstanceState)
    }

    /**
     * Выключает ВСТРОЕННУЮ автомаршрутизацию Flutter по deep link'ам.
     *
     * Входящие ссылки обрабатывает плагин app_links через
     * uriLinkStream в main.dart::_initDeepLinks. Но Android ОТДЕЛЬНО, в обход
     * этого плагина, отдаёт тот же самый intent движку Flutter напрямую как
     * «системный именованный маршрут» (канал flutter/navigation,
     * didPushRouteInformation → Navigator.pushNamed). У MaterialApp в
     * main.dart нет ни одного именованного маршрута, кроме "/" (вся
     * навигация в приложении императивная — Navigator.push, не pushNamed), и
     * onUnknownRoute не был задан — pushNamed падал с "Null check operator
     * used on a null value" прямо во время открытия ссылки.
     *
     * Чинить это подбором onUnknownRoute в Dart — лечить симптом: тогда для
     * КАЖДОЙ ссылки сработали бы ДВА независимых обработчика на один и тот же
     * intent (наш через app_links и обрезанный — через autoRoute), и рано
     * или поздно они разъехались бы по поведению. Правильно — выключить
     * дублирующий канал у источника, раз у нас уже есть один рабочий.
     * defence-in-depth на стороне Dart (onUnknownRoute в main.dart) всё равно
     * стоит — на случай, если когда-нибудь появится ещё один источник
     * pushNamed, о котором мы пока не знаем.
     */
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" ->
                        result.success(moveTaskToBack(true))

                    "showOverLockScreen" -> {
                        setShowOverLockScreen(true)
                        result.success(null)
                    }
                    "hideOverLockScreen" -> {
                        setShowOverLockScreen(false)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun setShowOverLockScreen(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            @Suppress("DEPRECATION")
            if (show) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
