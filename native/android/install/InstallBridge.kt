package com.deivid22srk.portix.install

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.toBitmap
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

// ============================================================================
// PORTIX — instalação pelo PackageInstaller PÚBLICO do framework (caminho
// Android normal). Contrato: lib/features/install/native_installer.dart — o
// Kotlin obedece o Dart (notas §4); eventos no formato exato de
// NativeInstallEvent (type/key/sessionId/error).
//
// Fluxos:
// - prepare (API 34+): cria a sessão (MODE_FULL_INSTALL + setSize),
//   decodifica o ícone já baixado pelo Dart (iconPng), pede a pré-aprovação
//   com PreapprovalDetails e devolve 'true'. O desenrolar chega por eventos:
//   'prepared' → 'preapprovalPending' (diálogo) → 'preapprovalApproved' /
//   'preapprovalDeclined' / 'preapprovalFailed'. API < 34: 'false' sem
//   evento — o Dart registra 'session-failed' e instala via commitFresh.
// - commitPrepared: escreve o APK na sessão pré-aprovada e faz commit (nenhum
//   diálogo novo no Android 14+).
// - commitFresh: sessão sem pré-aprovação (1 diálogo no commit — Android
//   ≤ 13 e primeira instalação de pacote desconhecido).
// - Receiver do status: EXTRA_STATUS == STATUS_PENDING_USER_ACTION →
//   startActivity(EXTRA_INTENT); STATUS_SUCCESS → aprovado/instalado;
//   STATUS_FAILURE_* → recusado/falha com código legível (notas §2.1).
//   EXTRA_PRE_APPROVAL distingue callbacks de pré-aprovação de callbacks de
//   instalação quando um broadcast atrasado cruza as fases.
// - abandon / cancelPrepare / cleanupOrphanSessions: limpeza (notas §2.2).
// ============================================================================

object InstallBridge {

    // Ação exclusiva do app para os broadcasts de status do PackageInstaller.
    private const val STATUS_ACTION = "com.deivid22srk.portix.action.INSTALL_STATUS"
    private const val EXTRA_KEY = "portix.key"
    private const val EXTRA_ATTEMPT = "portix.attemptId"

    /** Extra booleano do callback de pré-aprovação (valor exato, notas §2.1). */
    private const val PRE_APPROVAL_EXTRA = "android.content.pm.extra.PRE_APPROVAL"

    /** Pré-aprovação exige Android 14 (notas §2.2). */
    private const val MIN_PREAPPROVAL_SDK = Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    /**
     * Teto do ícone da pré-aprovação. O framework limita o tamanho; 256px
     * mantém o parcel do binder bem longe do limite de 1 MB (512×512
     * ARGB_8888 já beira o overflow).
     */
    private const val MAX_ICON_DIMENSION = 256

    private const val COPY_BUFFER_BYTES = 64 * 1024

    private val main = Handler(Looper.getMainLooper())

    /** Escrita de sessões (volumosa): single thread, uma sessão por vez. */
    private val sessionIo: ExecutorService = Executors.newSingleThreadExecutor()

    /**
     * Hashing em pool própria: o sha256 do Dart tem timeout de 10 min e NÃO
     * pode esperar a fila de escrita de um APK grande.
     */
    private val hashPool: ExecutorService = Executors.newCachedThreadPool()

    /** EventSink de `portix/install/events` (padrão do DownloaderBridge). */
    @Volatile
    var events: EventChannel.EventSink? = null

    /** Estado vivo por key: sessão aberta + receiver da fase atual. */
    private val pending = ConcurrentHashMap<String, InstallState>()

    private class InstallState(
        val sessionId: Int,
        val attemptId: Int,
        val packageName: String,
        val session: PackageInstaller.Session,
        @Volatile var receiver: BroadcastReceiver? = null,
    )

    // ------------------------------------------------------------- canal Dart

    fun freeBytes(context: Context): Long = PermissionBridge.freeBytes(context)

    /**
     * SHA-256 (hex minúsculo, sem prefixo) fora da main thread. Timeout de
     * 10 min é do Dart: digest não calculado = null = descarte (fail-closed).
     */
    fun sha256(path: String, result: MethodChannel.Result) {
        hashPool.execute {
            val digest = sha256Blocking(path)
            main.post { result.success(digest) }
        }
    }

    private fun sha256Blocking(path: String): String? {
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            return null
        }
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                val buffer = ByteArray(COPY_BUFFER_BYTES)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) {
                        break
                    }
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString(separator = "") { byte ->
                "%02x".format(byte.toInt() and 0xFF)
            }
        } catch (error: Throwable) {
            null
        }
    }

    // ---------------------------------------------------------------- prepare

    /**
     * Cria a sessão e pede a pré-aprovação. Devolve `true` quando a sessão
     * foi criada — o desenrolar chega por eventos ('prepared' primeiro, com
     * o sessionId que o Dart guarda no estado do fluxo).
     */
    fun prepare(
        context: Context,
        key: String,
        attemptId: Int,
        packageName: String,
        label: String,
        iconPng: ByteArray?,
        sizeBytes: Long,
    ): Boolean {
        if (key.isEmpty() || packageName.isEmpty()) {
            return false
        }
        // API < 34: sem pré-aprovação e sem sessão (o Dart cai no commitFresh
        // porque o sessionId fica nulo). Sem evento: o retorno `false` já
        // dispara FlowPreapproval('failed') no Dart — não duplicar.
        if (Build.VERSION.SDK_INT < MIN_PREAPPROVAL_SDK) {
            return false
        }
        // AttemptId monotônico: sessão pendente mais antiga do mesmo key é lixo.
        pending[key]?.let { stale ->
            if (stale.attemptId < attemptId) {
                discardState(context.applicationContext, key, stale, abandon = true)
            }
        }

        val appContext = context.applicationContext
        val installer = context.packageManager.packageInstaller
        var sessionId = 0
        var session: PackageInstaller.Session? = null
        try {
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            // Obrigatório > 0 antes do requestUserPreapproval (notas §2.2).
            // O Dart ainda manda 0 (tamanho desconhecido antes do download):
            // nesse caso não inventamos número.
            if (sizeBytes > 0L) {
                params.setSize(sizeBytes)
            }
            sessionId = installer.createSession(params)
            session = installer.openSession(sessionId)

            val state = InstallState(sessionId, attemptId, packageName, session)
            val receiver = statusReceiver(appContext, key, sessionId, phasePreapproval = true)
            ContextCompat.registerReceiver(
                appContext,
                receiver,
                IntentFilter(STATUS_ACTION),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            state.receiver = receiver
            pending[key] = state

            // O Dart guarda o sessionId agora (reducer 'prepared').
            emitEvent("prepared", key, sessionId)

            val details = PackageInstaller.PreapprovalDetails.Builder()
                .setIcon(approvalIcon(context, iconPng))
                .setLabel(
                    if (label.isNotEmpty()) label
                    else context.applicationInfo.loadLabel(context.packageManager).toString(),
                )
                .setPackageName(packageName)
                .build()
            session.requestUserPreapproval(
                details,
                statusPendingIntent(appContext, sessionId, key, attemptId).intentSender,
            )
            return true
        } catch (error: Throwable) {
            pending[key]?.let { stale ->
                unregisterQuietly(appContext, stale.receiver)
                pending.remove(key, stale)
            }
            session?.let { opened ->
                try {
                    opened.close()
                } catch (ignored: Throwable) {
                }
            }
            abandonSessionQuietly(appContext, sessionId)
            emitFailure("preapprovalFailed", key, sessionId.takeIf { it > 0 }, errorDebug(error))
            return false
        }
    }

    /** Ícone para o diálogo do sistema: bytes do Dart, fallback o do app. */
    private fun approvalIcon(context: Context, iconPng: ByteArray?): Bitmap {
        // Bytes HTTP podem ser gigantes/hostis: mede antes de decodificar e
        // usa inSampleSize para não estourar memória na thread de preparo.
        val decoded = if (iconPng != null && iconPng.isNotEmpty()) {
            try {
                val bounds = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeByteArray(iconPng, 0, iconPng.size, bounds)
                var sample = 1
                var largest = maxOf(bounds.outWidth, bounds.outHeight)
                while (largest > MAX_ICON_DIMENSION * 2) {
                    sample *= 2
                    largest /= 2
                }
                val options = BitmapFactory.Options().apply {
                    inSampleSize = sample
                }
                BitmapFactory.decodeByteArray(iconPng, 0, iconPng.size, options)
            } catch (error: Throwable) {
                null
            }
        } else {
            null
        }
        val source = decoded
            ?: context.applicationInfo.loadIcon(context.packageManager)
                .toBitmap(MAX_ICON_DIMENSION, MAX_ICON_DIMENSION)
        return bounded(source)
    }

    private fun bounded(bitmap: Bitmap): Bitmap {
        val largest = maxOf(bitmap.width, bitmap.height)
        if (largest <= MAX_ICON_DIMENSION || largest <= 0) {
            return bitmap
        }
        val scale = MAX_ICON_DIMENSION.toFloat() / largest
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
    }

    // ----------------------------------------------------------------- commit

    /**
     * Grava o APK na sessão pré-aprovada e faz commit. Nenhum diálogo novo
     * no Android 14+ (notas §2.2); o resultado chega por eventos.
     */
    fun commitPrepared(
        context: Context,
        key: String,
        sessionId: Int,
        path: String,
        expectedPackage: String?,
    ) {
        val appContext = context.applicationContext
        val state = pending[key]
        if (state == null || state.sessionId != sessionId) {
            emitFailure("failed", key, sessionId.takeIf { it > 0 }, "session-not-found")
            return
        }
        if (!expectedPackage.isNullOrEmpty() && expectedPackage != state.packageName) {
            emitFailure(
                "failed",
                key,
                sessionId,
                "package-mismatch ($expectedPackage != ${state.packageName})",
            )
            return
        }
        startCommit(appContext, key, state, File(path))
    }

    /**
     * Fluxo clássico: sessão sem pré-aprovação + commit (1 diálogo no
     * commit — Android ≤ 13 e primeira instalação, notas §2.3). Emite
     * 'prepared' também, para o Dart conseguir abandonar no cancelamento.
     */
    fun commitFresh(context: Context, key: String, path: String) {
        if (key.isEmpty()) {
            return
        }
        val appContext = context.applicationContext
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            emitFailure("failed", key, null, "file-not-found")
            return
        }
        val installer = context.packageManager.packageInstaller
        var sessionId = 0
        val session: PackageInstaller.Session = try {
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            sessionId = installer.createSession(params)
            installer.openSession(sessionId)
        } catch (error: Throwable) {
            abandonSessionQuietly(appContext, sessionId)
            emitFailure("failed", key, sessionId.takeIf { it > 0 }, errorDebug(error))
            return
        }

        val state = InstallState(sessionId, attemptId = 0, packageName = "", session)
        val receiver = statusReceiver(appContext, key, sessionId, phasePreapproval = false)
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            IntentFilter(STATUS_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        state.receiver = receiver
        pending[key] = state

        emitEvent("prepared", key, sessionId)
        startCommit(appContext, key, state, file)
    }

    /** Validações feitas; registra o receiver da fase de commit e escreve. */
    private fun startCommit(appContext: Context, key: String, state: InstallState, file: File) {
        registerCommitReceiver(appContext, key, state)
        emitEvent("writing", key, state.sessionId)
        sessionIo.execute {
            try {
                writeApk(state.session, file)
                emitEvent("committing", key, state.sessionId)
                state.session.commit(
                    statusPendingIntent(
                        appContext,
                        state.sessionId,
                        key,
                        state.attemptId,
                    ).intentSender,
                )
                state.session.close()
            } catch (error: Throwable) {
                discardState(appContext, key, state, abandon = true)
                emitFailure("installFailed", key, state.sessionId, errorDebug(error))
            }
        }
    }

    private fun registerCommitReceiver(context: Context, key: String, state: InstallState) {
        unregisterQuietly(context, state.receiver)
        state.receiver = null
        val receiver = statusReceiver(
            context,
            key,
            state.sessionId,
            phasePreapproval = false,
        )
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(STATUS_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        state.receiver = receiver
    }

    /** openWrite("portix.apk", 0, length) + cópia com buffer + fsync + close. */
    private fun writeApk(session: PackageInstaller.Session, file: File) {
        val out: OutputStream = session.openWrite("portix.apk", 0L, file.length())
        FileInputStream(file).use { input ->
            val buffer = ByteArray(COPY_BUFFER_BYTES)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) {
                    break
                }
                out.write(buffer, 0, read)
            }
            out.flush()
            session.fsync(out)
        }
        out.close()
    }

    // ------------------------------------------------------- receiver de status

    private fun statusReceiver(
        context: Context,
        key: String,
        sessionId: Int,
        phasePreapproval: Boolean,
    ): BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(receivedContext: Context?, intent: Intent?) {
            if (intent == null) {
                return
            }
            if (intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1) != sessionId) {
                return
            }
            if ((intent.getStringExtra(EXTRA_KEY) ?: key) != key) {
                return
            }
            val state = pending[key] ?: return
            // AttemptId monotônico: callbacks velhos são ignorados.
            if (intent.getIntExtra(EXTRA_ATTEMPT, Int.MIN_VALUE) < state.attemptId) {
                return
            }
            // EXTRA_PRE_APPROVAL distingue a fase quando um broadcast
            // atrasado cruza a troca de receivers; default = fase registrada.
            val preapproval = intent.getBooleanExtra(PRE_APPROVAL_EXTRA, phasePreapproval)
            if (preapproval) {
                onPreapprovalStatus(context, key, intent)
            } else {
                onCommitStatus(context, key, intent)
            }
        }
    }

    /** Callbacks da fase de pré-aprovação (sessão da chamada `prepare`). */
    private fun onPreapprovalStatus(context: Context, key: String, intent: Intent) {
        val state = pending[key] ?: return
        val sessionId = state.sessionId
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Diálogo ACTION_CONFIRM_PRE_APPROVAL (notas §2.2).
                emitEvent("preapprovalPending", key, sessionId)
                launchUserAction(context, intent, "preapprovalFailed", key, sessionId)
            }
            PackageInstaller.STATUS_SUCCESS -> {
                // Aprovado: sessão segue aberta para o commitPrepared.
                unregisterQuietly(context, state.receiver)
                state.receiver = null
                emitEvent("preapprovalApproved", key, sessionId)
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                // Recusa: abandona a sessão (notas §2.2).
                discardState(context, key, state, abandon = true)
                emitEvent("preapprovalDeclined", key, sessionId)
            }
            else -> {
                discardState(context, key, state, abandon = true)
                emitFailure("preapprovalFailed", key, sessionId, statusDebug(intent, status))
            }
        }
    }

    /** Callbacks da fase de commit (commitPrepared e commitFresh). */
    private fun onCommitStatus(context: Context, key: String, intent: Intent) {
        val state = pending[key] ?: return
        val sessionId = state.sessionId
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Diálogo de confirmação do install (Android ≤ 13 / fresh).
                emitEvent("userActionPending", key, sessionId)
                launchUserAction(context, intent, "installFailed", key, sessionId)
            }
            PackageInstaller.STATUS_SUCCESS -> {
                discardState(context, key, state, abandon = false)
                emitEvent("installDone", key, sessionId)
            }
            else -> {
                discardState(context, key, state, abandon = true)
                emitFailure("installFailed", key, sessionId, statusDebug(intent, status))
            }
        }
    }

    /** EXTRA_INTENT = intent do diálogo do sistema; NEW_TASK (app context). */
    private fun launchUserAction(
        context: Context,
        intent: Intent,
        failureType: String,
        key: String,
        sessionId: Int,
    ) {
        val userAction = extraIntent(intent)
        if (userAction == null) {
            emitFailure(failureType, key, sessionId, "missing-user-action-intent")
            return
        }
        try {
            userAction.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(userAction)
        } catch (error: Throwable) {
            emitFailure(failureType, key, sessionId, errorDebug(error))
        }
    }

    @Suppress("DEPRECATION")
    private fun extraIntent(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
    }

    // ------------------------------------------------------------- limpeza

    /** Abandona a sessão pelo id e limpa o estado interno, se houver. */
    fun abandon(context: Context, sessionId: Int) {
        if (sessionId <= 0) {
            return
        }
        val appContext = context.applicationContext
        val entry = pending.entries.firstOrNull { it.value.sessionId == sessionId }
        if (entry != null) {
            discardState(appContext, entry.key, entry.value, abandon = false)
        }
        abandonSessionQuietly(appContext, sessionId)
        // SecurityException (sessão de shell) cai no gancho do ShizukuBridge
        // (parte 4b) dentro de abandonSessionQuietly — aqui o silêncio é o
        // contrato.
    }

    /**
     * Cancela um prepare em andamento (impede o diálogo de pré-aprovação).
     * AttemptId monotônico: só mata estados de tentativas antigas/iguais.
     */
    fun cancelPrepare(context: Context, key: String, attemptId: Int) {
        val state = pending[key] ?: return
        if (state.attemptId > attemptId) {
            return
        }
        discardState(context.applicationContext, key, state, abandon = true)
    }

    /**
     * Sessões do próprio app sem dono vivo (app morto entre createSession e
     * commit). API 34+: getMySessions(); <34: getSessionInfos() filtrando o
     * packageName do app (notas §2.2). Sessões ativas têm dono: ficam.
     */
    fun cleanupOrphanSessions(context: Context) {
        val appContext = context.applicationContext
        sessionIo.execute {
            try {
                val installer = appContext.packageManager.packageInstaller
                // getMySessions (34+); abaixo disso getAllSessions com filtro
                // por installerPackageName (mesmo resultado para o app).
                val infos: List<PackageInstaller.SessionInfo> =
                    if (Build.VERSION.SDK_INT >= MIN_PREAPPROVAL_SDK) {
                        installer.mySessions
                    } else {
                        installer.allSessions
                    }
                for (info in infos) {
                    if (info.installerPackageName != appContext.packageName) {
                        continue
                    }
                    if (info.isActive) {
                        continue
                    }
                    try {
                        installer.abandonSession(info.sessionId)
                    } catch (ignored: Throwable) {
                        // Sessão já fechada: segue para as demais.
                    }
                }
            } catch (ignored: Throwable) {
                // Sem lista de sessões (OEM estranho): nada a limpar.
            }
        }
    }

    /** Unregister + remove do mapa (+ close/abandon quando marcado). */
    private fun discardState(
        context: Context,
        key: String,
        state: InstallState,
        abandon: Boolean,
    ) {
        unregisterQuietly(context, state.receiver)
        state.receiver = null
        pending.remove(key, state)
        if (abandon) {
            try {
                state.session.close()
            } catch (ignored: Throwable) {
            }
            abandonSessionQuietly(context, state.sessionId)
        }
    }

    private fun unregisterQuietly(context: Context, receiver: BroadcastReceiver?) {
        if (receiver == null) {
            return
        }
        try {
            context.unregisterReceiver(receiver)
        } catch (ignored: Throwable) {
        }
    }

    private fun abandonSessionQuietly(context: Context, sessionId: Int) {
        if (sessionId <= 0) {
            return
        }
        try {
            context.packageManager.packageInstaller.abandonSession(sessionId)
        } catch (ignored: Throwable) {
            // Sessão de shell (criada pelo caminho Shizuku) dá SecurityException:
            // o gancho da parte 4b tenta o abandon pelo binder do Shizuku.
            ShizukuBridge.abandonViaShizuku(context, sessionId)
        }
    }

    // ------------------------------------------------------------------ extras

    /** PendingIntent MUTABLE | UPDATE_CURRENT (D6/notas §2.2 — obrigatório). */
    private fun statusPendingIntent(
        context: Context,
        sessionId: Int,
        key: String,
        attemptId: Int,
    ): PendingIntent {
        val intent = Intent(STATUS_ACTION)
            .setPackage(context.packageName)
            .putExtra(EXTRA_KEY, key)
            .putExtra(EXTRA_ATTEMPT, attemptId)
        return PendingIntent.getBroadcast(
            context,
            sessionId,
            intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun emitEvent(type: String, key: String, sessionId: Int?) {
        emit(mapOf("type" to type, "key" to key, "sessionId" to sessionId))
    }

    private fun emitFailure(type: String, key: String, sessionId: Int?, error: String) {
        emit(mapOf("type" to type, "key" to key, "sessionId" to sessionId, "error" to error))
    }

    /** Eventos sempre na thread principal (padrão do DownloaderBridge). */
    private fun emit(event: Map<String, Any?>) {
        val sink = events ?: return
        main.post { sink.success(event) }
    }

    /** Nomes de status do PackageInstaller (constantes reais, notas §2.1/D9). */
    private fun statusName(status: Int): String = when (status) {
        PackageInstaller.STATUS_PENDING_USER_ACTION -> "pending-user-action"
        PackageInstaller.STATUS_SUCCESS -> "success"
        PackageInstaller.STATUS_FAILURE -> "failure"
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
        PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
        PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
        PackageInstaller.STATUS_FAILURE_TIMEOUT -> "timeout"
        else -> "unknown"
    }

    private fun statusDebug(intent: Intent, status: Int): String {
        val name = statusName(status)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        return if (message.isNullOrEmpty()) "$name($status)" else "$name($status) $message"
    }

    private fun errorDebug(error: Throwable): String {
        val message = error.message
        return if (message.isNullOrEmpty()) {
            error.javaClass.simpleName
        } else {
            "${error.javaClass.simpleName}: $message"
        }
    }
}
