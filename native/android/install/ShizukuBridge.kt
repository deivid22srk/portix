package com.deivid22srk.portix.install

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IIntentSender
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.IPackageInstaller
import android.content.pm.IPackageInstallerSession
import android.content.pm.IPackageManager
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.Os
import androidx.core.content.ContextCompat
import rikka.shizuku.Shizuku
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.lsposed.hiddenapibypass.HiddenApiBypass

// ============================================================================
// PORTIX — estado do Shizuku e instalação silenciosa pelo binder do servidor
// (caminho Shizuku). Contrato: lib/features/install/shizuku.dart — o Kotlin
// obedece o Dart (notas §4).
//
// Canal `portix/shizuku` (métodos que o Dart chama):
// - status            → String com o nome do estado (ShizukuStatus.decode).
// - requestPermission → void; o RESULTADO chega pelo stream de eventos
//                       ("não há retorno direto", shizuku.dart).
// - openShizuku       → bool (launcher do app Shizuku; Dart ignora).
// - install(key, path, expectedPackage) → instalação silenciosa; o Dart
//   chama este método em install_flow.dart (_runInstall, plano shizuku) e
//   IGNORA o retorno — o desenrolar chega por eventos no canal
//   `portix/install/events` (formato NativeInstallEvent) porque é o ÚNICO
//   stream que o fluxo de instalação escuta. O retorno {ok, sessionId} é
//   apenas informativo.
//
// Canal `portix/shizuku/events` (EventChannel): mapa {"status": nome} com
// os 4 estados EXATOS do Dart — notInstalled / installedStopped /
// runningNoPermission / active (notas §1.3). Emite o estado sticky no
// onListen + cada mudança em tempo real (binder received/dead e resultado
// da permissão). Toda mudança também atualiza PermissionBridge.shizukuStatus
// (D28), que o snapshot de portix/permissions lê.
//
// Estados (notas §1.3 — ordem de avaliação):
// - notInstalled: getPackageInfo(moe.shizuku.privileged.api, 0) →
//   NameNotFoundException (try/catch compila mesmo sem <queries>).
// - installedStopped: instalado mas Shizuku.pingBinder() == false.
// - runningNoPermission: pingBinder true e checkSelfPermission != granted.
// - active: pingBinder true && checkSelfPermission == PERMISSION_GRANTED.
//
// Instalação (receita do demo oficial, notas §1.6): binder do serviço
// "package" → ShizukuBinderWrapper → IPackageManager.Stub.asInterface →
// getPackageInstaller() → createSession(MODE_FULL_INSTALL + flag de
// downgrade) → openSession → openWrite/write/fsync/close → commit com
// PendingIntent MUTABLE (receiver NOT_EXPORTED, D6 — igual ao caminho
// Android). SessionParams NÃO é reescrito: o pacote é o público do
// framework; as interfaces ocultas vêm das stubs compile-only (D18), que
// prevalecem reais em runtime pelo boot classpath.
//
// Defesa: TODAS as chamadas Shizuku passam por pingBinder/ready e por
// try/catch que emite evento 'failed' legível — o Dart oferece o fallback
// "usar Android desta vez". Nenhuma chamada solta pode virar
// IllegalStateException no Dart.
// ============================================================================

object ShizukuBridge {

    /** Pacote do app Shizuku (notas §1.2/§1.3). */
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    /** requestCode próprio do pedido de permissão (4711/4712 são do app). */
    private const val REQUEST_PERMISSION_CODE = 4721

    /** INSTALL_ALLOW_DOWNGRADE (valor real do framework, notas §1.6). */
    private const val INSTALL_ALLOW_DOWNGRADE = 0x00100000

    /** Nomes EXATOS aceitos por ShizukuStatus.decode (shizuku.dart). */
    private const val STATE_NOT_INSTALLED = "notInstalled"
    private const val STATE_INSTALLED_STOPPED = "installedStopped"
    private const val STATE_RUNNING_NO_PERMISSION = "runningNoPermission"
    private const val STATE_ACTIVE = "active"

    private const val COPY_BUFFER_BYTES = 64 * 1024

    /** Ação exclusiva do app para os broadcasts de status do caminho Shizuku. */
    private const val STATUS_ACTION = "com.deivid22srk.portix.action.SHIZUKU_INSTALL_STATUS"

    /** Extra próprio do receiver (padrão do InstallBridge). */
    private const val EXTRA_KEY = "portix.key"

    /**
     * Candidatos REAIS para o wrapper do binder — o pacote varia entre
     * artefatos/versões do shizuku-api (rikka.shizuku.* vs dev.rikka.shizuku.*).
     * Reflexão com candidatos evita quebrar o CI em cima de um import incerto
     * (regra da tarefa: alternativa mais defensiva p/ símbolos incertos do
     * demo). Falha em runtime → evento 'failed' → fallback do Dart.
     */
    private val WRAPPER_CANDIDATES =
        arrayOf("rikka.shizuku.ShizukuBinderWrapper", "dev.rikka.shizuku.ShizukuBinderWrapper")

    private val main = Handler(Looper.getMainLooper())

    /** Escrita da sessão Shizuku (volumosa): single thread, uma por vez. */
    private val shizukuIo: ExecutorService = Executors.newSingleThreadExecutor()

    /** EventSink de `portix/shizuku/events` (padrão DownloaderBridge). */
    @Volatile
    var events: EventChannel.EventSink? = null

    /** Contexto do app guardado no attach para os callbacks dos listeners. */
    @Volatile
    private var appContext: Context? = null

    private var listenersRegistered = false

    /** Receivers de status vivos por sessionId (removidos nos terminais). */
    private val receivers = ConcurrentHashMap<Int, BroadcastReceiver>()

    // ------------------------------------------------------------- listeners

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        emitStatus(currentState())
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        emitStatus(currentState())
    }

    private val requestResultListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        if (requestCode == REQUEST_PERMISSION_CODE) {
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            // Aceito + binder vivo → active direto; qualquer outro caso
            // recalcula: recusa volta a runningNoPermission e binder morto
            // cai em installedStopped/notInstalled (fonte = servidor).
            emitStatus(if (granted && isBinderReady()) STATE_ACTIVE else currentState())
        }
    }

    // ------------------------------------------------------------ attach/etc

    /**
     * Chamado no configureFlutterEngine e a cada onListen do EventChannel.
     * Idempotente: guarda o contexto, garante listeners + isenções e emite o
     * estado sticky para quem acabou de assinar.
     */
    fun attach(context: Context) {
        appContext = context.applicationContext
        ensureSetup()
        emitStatus(currentState())
    }

    /**
     * Estado atual (leitura do Dart via `status`). Recalcula SEMPRE — nunca
     * confia em cache (o servidor Shizuku pode mudar por fora).
     */
    fun status(context: Context): String {
        appContext = context.applicationContext
        ensureSetup()
        val state = currentState()
        emitStatus(state)
        return state
    }

    /**
     * Pede a permissão ao app Shizuku (diálogo do Shizuku). Sem retorno ao
     * Dart: o resultado chega pelo stream (requestResultListener → estado).
     */
    fun requestPermission() {
        ensureSetup()
        val ready = try {
            Shizuku.pingBinder()
        } catch (error: Throwable) {
            false
        }
        if (!ready) {
            // Sem servidor não há diálogo; estado atual segue pelo stream.
            emitStatus(currentState())
            return
        }
        try {
            Shizuku.requestPermission(REQUEST_PERMISSION_CODE)
        } catch (error: Throwable) {
            emitStatus(currentState())
        }
    }

    /** Abre o app Shizuku (usuário inicia o servidor). Queries do D32. */
    fun openShizuku(context: Context): Boolean {
        return try {
            val appCtx = context.applicationContext
            val intent = appCtx.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
                ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appCtx.startActivity(intent)
            true
        } catch (error: Throwable) {
            false
        }
    }

    /** Remove os três listeners (par dos adds) — teardown futuro. */
    fun release() {
        synchronized(this) {
            if (!listenersRegistered) {
                return
            }
            try {
                Shizuku.removeBinderReceivedListener(binderReceivedListener)
            } catch (ignored: Throwable) {
            }
            try {
                Shizuku.removeBinderDeadListener(binderDeadListener)
            } catch (ignored: Throwable) {
            }
            try {
                Shizuku.removeRequestPermissionResultListener(requestResultListener)
            } catch (ignored: Throwable) {
            }
            listenersRegistered = false
        }
    }

    // --------------------------------------------------------------- setup

    /**
     * Isenções de API oculta (uma vez) + listeners do Shizuku (uma vez).
     * Prefixos: Landroid/content/ (stubs pm), Landroid/os/ (ServiceManager) e
     * Landroid/app/ (PendingIntent.getIntentSender() é @hide — reflexão da
     * tarefa; a isenção extra citada na 4b).
     */
    private fun ensureSetup() {
        if (listenersRegistered) {
            return
        }
        synchronized(this) {
            if (listenersRegistered) {
                return
            }
            try {
                HiddenApiBypass.addHiddenApiExemptions(
                    "Landroid/content/",
                    "Landroid/os/",
                    "Landroid/app/",
                )
            } catch (ignored: Throwable) {
            }
            try {
                Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
                Shizuku.addBinderDeadListener(binderDeadListener)
                Shizuku.addRequestPermissionResultListener(requestResultListener)
                listenersRegistered = true
            } catch (error: Throwable) {
                // API indisponível (build sem provider?): estado segue default.
            }
        }
    }

    // ---------------------------------------------------------------- estado

    /** Estados §1.3 na ordem exata; nunca lança (try/catch em cada etapa). */
    private fun currentState(): String {
        val context = appContext ?: return STATE_NOT_INSTALLED
        val installed = try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            true
        } catch (error: PackageManager.NameNotFoundException) {
            false
        } catch (error: Throwable) {
            false
        }
        if (!installed) {
            return STATE_NOT_INSTALLED
        }
        val ready = try {
            Shizuku.pingBinder()
        } catch (error: Throwable) {
            false
        }
        if (!ready) {
            return STATE_INSTALLED_STOPPED
        }
        val granted = try {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (error: Throwable) {
            false
        }
        return if (granted) STATE_ACTIVE else STATE_RUNNING_NO_PERMISSION
    }

    private fun isBinderReady(): Boolean {
        return try {
            // Short-circuit: checkSelfPermission só depois de pingBinder vivo
            // (R2 — binder morto não pode virar IllegalStateException).
            Shizuku.pingBinder() &&
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (error: Throwable) {
            false
        }
    }

    /**
     * Publica o estado: PermissionBridge.shizukuStatus sempre (D28 — snapshot
     * de portix/permissions) e o EventChannel quando alguém está ouvindo.
     * Sink sempre na thread principal (padrão DownloaderBridge).
     */
    private fun emitStatus(state: String) {
        PermissionBridge.shizukuStatus = state
        val sink = events ?: return
        main.post { sink.success(mapOf("status" to state)) }
    }

    // -------------------------------------------------------------- instalação

    /**
     * Instalação silenciosa (plano shizuku de install_flow.dart). O Dart já
     * rechecou `status.isActive`; rechecamos aqui por defesa. O trabalho
     * pesado vai para [shizukuIo]; a resposta é imediata porque o Dart ignora
     * o retorno e segue por eventos.
     */
    fun install(context: Context, key: String, path: String, expectedPackage: String?): Map<String, Any?> {
        val appCtx = context.applicationContext
        appContext = appCtx
        ensureSetup()
        if (key.isEmpty() || path.isEmpty()) {
            emitInstallFailure("failed", key, null, "invalid-arguments")
            return mapOf("ok" to false, "sessionId" to null)
        }
        val state = currentState()
        emitStatus(state)
        if (state != STATE_ACTIVE) {
            // Token EXATO que o Dart casa (offerFallback automático); o estado
            // vai nos logs, não na mensagem de erro.
            emitInstallFailure("failed", key, null, "shizuku-unavailable")
            return mapOf("ok" to false, "sessionId" to null)
        }
        shizukuIo.execute { installBlocking(appCtx, key, path, expectedPackage) }
        return mapOf("ok" to true, "sessionId" to null)
    }

    /** Receita §1.6 inteira em try/catch único: qualquer falha → 'failed'. */
    private fun installBlocking(context: Context, key: String, path: String, expectedPackage: String?) {
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            emitInstallFailure("failed", key, null, "file-not-found")
            return
        }
        if (!expectedPackage.isNullOrEmpty()) {
            val archive = try {
                context.packageManager.getPackageArchiveInfo(path, 0)
            } catch (error: Throwable) {
                null
            }
            val archivePackage = archive?.packageName
            if (!archivePackage.isNullOrEmpty() && archivePackage != expectedPackage) {
                emitInstallFailure(
                    "failed",
                    key,
                    null,
                    "package-mismatch ($expectedPackage != $archivePackage)",
                )
                return
            }
        }
        if (!isBinderReady()) {
            emitInstallFailure("failed", key, null, "shizuku-binder-dead")
            return
        }

        var sessionId = 0
        var session: IPackageInstallerSession? = null
        try {
            val rawBinder = packageServiceBinder()
                ?: throw IllegalStateException("package service binder unavailable")
            val wrapper = shizukuWrapper(rawBinder)
                ?: throw IllegalStateException("ShizukuBinderWrapper unavailable")
            val pm = IPackageManager.Stub.asInterface(wrapper)
            val installer = pm.getPackageInstaller()
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            allowDowngrade(params)
            sessionId = invokeCreateSession(installer, params, context)
            // Local não-nulo: evita smart cast de var capturada por closure
            // (as chamadas seguintes ficam em lambda `use`).
            val opened: IPackageInstallerSession = installer.openSession(sessionId)
            session = opened

            val receiver = statusReceiver(key, sessionId)
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(STATUS_ACTION),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receivers[sessionId] = receiver

            emitInstallEvent("prepared", key, sessionId)
            emitInstallEvent("writing", key, sessionId)
            // AIDL real: openWrite devolve ParcelFileDescriptor transferido pelo
            // binder — a escrita é LOCAL no FD e o sync também (não existe
            // fsync na AIDL; o sync do lado remoto acontece no close).
            val pfd: ParcelFileDescriptor = opened.openWrite("portix.apk", 0L, file.length())
            try {
                FileOutputStream(pfd.fileDescriptor).use { out ->
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
                    }
                    try {
                        Os.fsync(pfd.fileDescriptor)
                    } catch (ignored: Throwable) {
                    }
                }
            } finally {
                try {
                    pfd.close()
                } catch (ignored: Throwable) {
                }
            }
            opened.close()
            emitInstallEvent("committing", key, sessionId)
            invokeCommit(opened, intentSenderOf(statusPendingIntent(context, sessionId, key)))
        } catch (error: Throwable) {
            unregisterQuietly(context, sessionId)
            session?.let { opened ->
                try {
                    opened.close()
                } catch (ignored: Throwable) {
                }
            }
            abandonViaShizuku(context, sessionId)
            emitInstallFailure("installFailed", key, sessionId.takeIf { it > 0 }, errorDebug(error))
        }
    }


    /**
     * createSession pela AIDL real do device: 4 args (12+), 3 (11) e 2 (10-).
     * O objeto é um proxy da interface REAL (framework), então os métodos
     * existentes variam conforme a versão — tenta da mais nova para a mais velha.
     */
    private fun invokeCreateSession(
        installer: Any,
        params: PackageInstaller.SessionParams,
        context: Context,
    ): Int {
        val methods = installer.javaClass.methods.filter { it.name == "createSession" }
        // myUserId é @hide: uid/100000 dá o MESMO índice de usuário (público).
        val userId = Process.myUid() / 100000
        val sorted = methods.sortedByDescending { it.parameterCount }
        for (method in sorted) {
            try {
                return when (method.parameterCount) {
                    4 -> method.invoke(installer, params, context.packageName, null, userId) as Int
                    3 -> method.invoke(installer, params, context.packageName, userId) as Int
                    2 -> method.invoke(installer, params, context.packageName) as Int
                    else -> continue
                }
            } catch (ignored: Throwable) {
                // Tenta a assinatura seguinte (versão diferente do SO).
            }
        }
        throw IllegalStateException("createSession indisponível via Shizuku")
    }

    /**
     * commit pela AIDL real: 2 args (14+, forTransferred) ou 1 arg (13-).
     * O statusReceiver chega como broadcast no PendingIntent do próprio app.
     */
    private fun invokeCommit(session: Any, sender: Any) {
        val methods = session.javaClass.methods.filter { it.name == "commit" }
        for (method in methods.sortedByDescending { it.parameterCount }) {
            try {
                when (method.parameterCount) {
                    2 -> {
                        method.invoke(session, sender, false)
                        return
                    }
                    1 -> {
                        method.invoke(session, sender)
                        return
                    }
                    else -> continue
                }
            } catch (ignored: Throwable) {
                // Tenta a assinatura seguinte (versão diferente do SO).
            }
        }
        throw IllegalStateException("commit indisponível via Shizuku")
    }

    // ---------------------------------------------------------- binder hidden

    /**
     * IBinder cru do serviço "package". Caminho do demo:
     * rikka.shizuku.SystemServiceHelper.getSystemService("package") — classe
     * confirmada no jar 13.1.5; reflexão com fallback = ServiceManager
     * (hidden — isenção Landroid/os/ cobre a reflexão) via reflexão simples e
     * via HiddenApiBypass.invoke como terceira tentativa.
     */
    private fun packageServiceBinder(): IBinder? {
        try {
            val helper = Class.forName("rikka.shizuku.SystemServiceHelper")
            val method = helper.getDeclaredMethod("getSystemService", String::class.java)
            val binder = method.invoke(null, "package")
            if (binder is IBinder) {
                return binder
            }
        } catch (ignored: Throwable) {
        }
        try {
            val manager = Class.forName("android.os.ServiceManager")
            val method = manager.getMethod("getService", String::class.java)
            val binder = method.invoke(null, "package")
            if (binder is IBinder) {
                return binder
            }
        } catch (ignored: Throwable) {
        }
        return try {
            val manager = Class.forName("android.os.ServiceManager")
            val binder = HiddenApiBypass.invoke(manager, null, "getService", "package")
            binder as? IBinder
        } catch (error: Throwable) {
            null
        }
    }

    /** Wrapper do Shizuku (transact como shell) — candidatos em [WRAPPER_CANDIDATES]. */
    private fun shizukuWrapper(raw: IBinder): IBinder? {
        for (name in WRAPPER_CANDIDATES) {
            try {
                val type = Class.forName(name)
                val constructor = type.getDeclaredConstructor(IBinder::class.java)
                val wrapper = constructor.newInstance(raw)
                if (wrapper is IBinder) {
                    return wrapper
                }
            } catch (ignored: Throwable) {
            }
        }
        return null
    }

    /**
     * installFlags |= INSTALL_ALLOW_DOWNGRADE. O campo é hidden (@hide):
     * reflexão coberta pela isenção "Landroid/content/" (classe
     * android.content.pm.PackageInstaller$SessionParams).
     */
    private fun allowDowngrade(params: PackageInstaller.SessionParams) {
        try {
            val field = PackageInstaller.SessionParams::class.java.getDeclaredField("installFlags")
            field.isAccessible = true
            field.setInt(params, field.getInt(params) or INSTALL_ALLOW_DOWNGRADE)
        } catch (ignored: Throwable) {
            // Campo renomeado/ausente: segue sem a flag (só afeta downgrade).
        }
    }

    /**
     * PendingIntent.getIntentSender() é @hide @UnsupportedAppUsage — reflexão
     * coberta pela isenção "Landroid/app/". O cast para android.content.
     * IIntentSender resolve no boot classpath em runtime (classe real).
     */
    private fun intentSenderOf(pendingIntent: PendingIntent): IIntentSender {
        val method = PendingIntent::class.java.getDeclaredMethod("getIntentSender")
        method.isAccessible = true
        return method.invoke(pendingIntent) as IIntentSender
    }

    // ------------------------------------------------- receiver de status (D6)

    /**
     * PendingIntent MUTABLE | UPDATE_CURRENT (D24) + receiver NOT_EXPORTED
     * (D6) — o mesmo padrão do caminho Android; o broadcast do sistema chega
     * pelo PendingIntent criado pelo app.
     */
    private fun statusPendingIntent(context: Context, sessionId: Int, key: String): PendingIntent {
        val intent = Intent(STATUS_ACTION)
            .setPackage(context.packageName)
            .putExtra(EXTRA_KEY, key)
        return PendingIntent.getBroadcast(
            context,
            sessionId,
            intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Callbacks da fase de commit do caminho Shizuku (sem pré-aprovação). */
    private fun statusReceiver(key: String, sessionId: Int): BroadcastReceiver =
        object : BroadcastReceiver() {
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
                val context = receivedContext ?: appContext
                when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        // Diálogo de confirmação do install (Android ≤ 13 /
                        // pacote desconhecido) — mesmo roteiro do commitFresh.
                        emitInstallEvent("userActionPending", key, sessionId)
                        launchUserAction(context, intent, key, sessionId)
                    }
                    PackageInstaller.STATUS_SUCCESS -> {
                        unregisterQuietly(context, sessionId)
                        emitInstallEvent("installDone", key, sessionId)
                    }
                    else -> {
                        unregisterQuietly(context, sessionId)
                        emitInstallFailure("installFailed", key, sessionId, statusDebug(intent, status))
                    }
                }
            }
        }

    /** EXTRA_INTENT = intent do diálogo do sistema; NEW_TASK (app context). */
    private fun launchUserAction(context: Context?, intent: Intent, key: String, sessionId: Int) {
        if (context == null) {
            emitInstallFailure("installFailed", key, sessionId, "missing-context-for-user-action")
            return
        }
        val userAction = extraIntent(intent)
        if (userAction == null) {
            emitInstallFailure("installFailed", key, sessionId, "missing-user-action-intent")
            return
        }
        try {
            userAction.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(userAction)
        } catch (error: Throwable) {
            emitInstallFailure("installFailed", key, sessionId, errorDebug(error))
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

    // ---------------------------------------------------------------- gancho

    /**
     * Gancho citado na 4a: sessões criadas pelo caminho Android pertencem ao
     * shell quando vieram do Shizuku — o PackageInstaller do app dá
     * SecurityException no abandon. InstallBridge.abandonSessionQuietly chama
     * este hook no catch. Fire-and-forget: falha nunca derruba o chamador.
     */
    fun abandonViaShizuku(context: Context, sessionId: Int) {
        if (sessionId <= 0) {
            return
        }
        val appCtx = context.applicationContext
        appContext = appCtx
        ensureSetup()
        if (!isBinderReady()) {
            return
        }
        try {
            val rawBinder = packageServiceBinder() ?: return
            val wrapper = shizukuWrapper(rawBinder) ?: return
            val installer = IPackageManager.Stub.asInterface(wrapper).getPackageInstaller()
            installer.abandonSession(sessionId)
        } catch (ignored: Throwable) {
        }
    }

    // ---------------------------------------------------------------- eventos

    private fun unregisterQuietly(context: Context?, sessionId: Int) {
        val receiver = receivers.remove(sessionId) ?: return
        if (context == null) {
            return
        }
        try {
            context.unregisterReceiver(receiver)
        } catch (ignored: Throwable) {
        }
    }

    /** Eventos de instalação vão para portix/install/events (InstallBridge). */
    private fun emitInstallEvent(type: String, key: String, sessionId: Int?) {
        val event = mapOf("type" to type, "key" to key, "sessionId" to sessionId)
        main.post { InstallBridge.events?.success(event) }
    }

    private fun emitInstallFailure(type: String, key: String, sessionId: Int?, error: String) {
        val event = mapOf("type" to type, "key" to key, "sessionId" to sessionId, "error" to error)
        main.post { InstallBridge.events?.success(event) }
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
