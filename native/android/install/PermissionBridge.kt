package com.deivid22srk.portix.install

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel
import java.io.File

// ============================================================================
// PORTIX — ponte de permissões (canal `portix/permissions`).
//
// Contrato: lib/features/install/permissions.dart — o Kotlin obedece o Dart
// (notas §4). O snapshot devolve EXATAMENTE os campos que o Dart lê:
// canInstallApps / notificationsGranted / shizuku / sdkInt / freeBytes /
// isAndroid (sempre true no Kotlin). Fora de API 33 as notificações são
// implícitas; abaixo da API 26 não existe "instalar apps desconhecidos".
// ============================================================================

object PermissionBridge {

    /** Código de request do POST_NOTIFICATIONS (4711 é do canal de download). */
    private const val REQUEST_POST_NOTIFICATIONS = 4712

    /**
     * Nome do estado Shizuku no formato que `ShizukuStatus.decode` espera
     * (notInstalled / installedStopped / runningNoPermission / active).
     * Valor default seguro; o ShizukuBridge (parte 4b) atualiza em tempo real
     * — o snapshot é revalidado pelo Dart quando o estado muda.
     */
    @Volatile
    var shizukuStatus: String = "notInstalled"

    /** Result do `requestNotifications` aguardando o diálogo do sistema. */
    private var pendingNotificationsResult: MethodChannel.Result? = null

    /** Snapshot no formato exato de `PermissionSnapshot` (permissions.dart). */
    fun snapshot(context: Context): Map<String, Any?> {
        val canInstallApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                context.packageManager.canRequestPackageInstalls()
            } catch (error: Throwable) {
                false
            }
        } else {
            // Antes da API 26 não existe a restrição por app.
            true
        }
        val notificationsGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                NotificationManagerCompat.from(context).areNotificationsEnabled()
            } catch (error: Throwable) {
                false
            }
        } else {
            // Permissão implícita (notas §2.3 / contrato de permissions.dart).
            true
        }
        return mapOf(
            "canInstallApps" to canInstallApps,
            "notificationsGranted" to notificationsGranted,
            "shizuku" to shizukuStatus,
            "sdkInt" to Build.VERSION.SDK_INT,
            "freeBytes" to freeBytes(context),
            "isAndroid" to true,
        )
    }

    /**
     * Abre "Instalar apps desconhecidos" já direcionada ao PORTIX
     * (ACTION_MANAGE_UNKNOWN_APP_SOURCES + `package:<appId>`, notas §2.3).
     * `activity.packageName` é `com.deivid22srk.portix` em runtime.
     */
    fun openInstallAppsSettings(activity: Activity): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:${activity.packageName}"))
            activity.startActivity(intent)
            true
        } catch (error: Throwable) {
            // Tela indisponível (raro): o sheet do app continua com o contexto.
            false
        }
    }

    /**
     * Pede POST_NOTIFICATIONS (Android 13+). O resultado do diálogo chega
     * async em [onRequestPermissionsResult]; a pendência antiga é resolvida
     * com `false` para nunca deixar o Dart esperando duas respostas.
     */
    fun requestNotifications(activity: Activity, result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            NotificationManagerCompat.from(activity).areNotificationsEnabled()
        ) {
            result.success(true)
            return
        }
        pendingNotificationsResult?.success(false)
        pendingNotificationsResult = result
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_POST_NOTIFICATIONS,
            )
        } catch (error: Throwable) {
            pendingNotificationsResult = null
            result.success(false)
        }
    }

    /** Entrega ao Dart o resultado do diálogo de notificações. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) {
            return
        }
        val pending = pendingNotificationsResult
        pendingNotificationsResult = null
        pending?.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    /**
     * Bytes livres no diretório dos APKs — o MESMO diretório do
     * DownloadService (`getExternalFilesDir(null)/apk`). -1 = desconhecido.
     */
    fun freeBytes(context: Context): Long {
        return try {
            val parent = context.getExternalFilesDir(null) ?: return -1L
            val dir = File(parent, "apk")
            dir.mkdirs()
            StatFs(dir.absolutePath).availableBytes
        } catch (error: Throwable) {
            -1L
        }
    }
}
