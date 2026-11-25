package com.glitch.ringtone

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Системные настройки, от которых зависит, дойдёт ли звонок до человека.
 *
 * ЧЕМ ЭТО ОТЛИЧАЕТСЯ ОТ ОБЫЧНЫХ РАЗРЕШЕНИЙ. Микрофон, камеру и уведомления
 * приложение спрашивает штатным способом (permission_handler). А здесь собрано
 * то, что штатным способом не спрашивается вовсе:
 *
 *   • работа в фоне — отдельный системный запрос, не «разрешение»;
 *   • полноэкранный вызов — с Android 14 выдаётся не всем и просится через
 *     отдельный экран настроек;
 *   • автозапуск — вообще не Android, а надстройка производителя прошивки.
 *
 * ПРО АВТОЗАПУСК ОТДЕЛЬНО. Ни узнать его состояние, ни включить программно
 * нельзя — публичного способа не существует ни у нас, ни у кого-либо ещё.
 * Единственное, что можно, — открыть человеку нужный экран прошивки. Адреса
 * этих экранов у каждого производителя свои и меняются от версии к версии,
 * поэтому каждый вариант пробуется по очереди, а если не подошёл ни один —
 * открываются обычные настройки приложения. Молча не падаем ни при каком
 * раскладе: экран настроек приложения есть всегда.
 */
object CallSystemSettings {

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        return try {
            val power = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                ?: return false
            power.isIgnoringBatteryOptimizations(context.packageName)
        } catch (e: Exception) {
            false
        }
    }

    fun requestIgnoreBatteryOptimizations(context: Context) {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (!startSafely(context, direct)) {
            val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (!startSafely(context, list)) openAppSettings(context)
        }
    }

    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as? NotificationManager ?: return false
            manager.canUseFullScreenIntent()
        } catch (e: Exception) {
            false
        }
    }

    fun hasFullScreenSetting(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    fun openFullScreenIntentSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (startSafely(context, intent)) return
        }
        openAppSettings(context)
    }

    private val AUTOSTART_SCREENS = listOf(
        // Huawei / Honor
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        // Xiaomi / Redmi / POCO
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        // Oppo / realme
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        // Vivo
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
        "com.asus.mobilemanager" to "com.asus.mobilemanager.MainActivity",
    )

    fun hasAutostartSettings(context: Context): Boolean =
        AUTOSTART_SCREENS.any { (pkg, cls) -> resolves(context, pkg, cls) }

    fun openAutostartSettings(context: Context) {
        for ((pkg, cls) in AUTOSTART_SCREENS) {
            if (!resolves(context, pkg, cls)) continue
            val intent = Intent().apply {
                component = ComponentName(pkg, cls)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (startSafely(context, intent)) return
        }
        openAppSettings(context)
    }

    private const val MIUI_PERM_EDITOR_PKG = "com.miui.securitycenter"
    private const val MIUI_PERM_EDITOR_CLS =
        "com.miui.permcenter.permissions.PermissionsEditorActivity"

    fun hasLockScreenPermissionScreen(context: Context): Boolean =
        resolves(context, MIUI_PERM_EDITOR_PKG, MIUI_PERM_EDITOR_CLS)

    fun openLockScreenPermissionSettings(context: Context) {
        val intent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
            setClassName(MIUI_PERM_EDITOR_PKG, MIUI_PERM_EDITOR_CLS)
            putExtra("extra_pkgname", context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (!startSafely(context, intent)) openAppSettings(context)
    }

    fun openAppSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startSafely(context, intent)
    }

    private fun resolves(context: Context, pkg: String, cls: String): Boolean = try {
        val intent = Intent().setComponent(ComponentName(pkg, cls))
        context.packageManager.resolveActivity(intent, 0) != null
    } catch (e: Exception) {
        false
    }

    private fun startSafely(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }
}
