package android.content.pm

import android.content.IIntentSender
import android.os.Binder
import android.os.IBinder
import android.os.IInterface
import java.io.OutputStream

// ============================================================================
// Stubs compile-only das interfaces ocultas do binder "package" — o mesmo
// padrão do demo oficial (RikkaApps/Shizuku-API): classes declaradas nos
// MESMOS nomes qualificados do framework; em runtime o classloader de boot
// prevalece e as classes REAIS do Android são usadas, então os corpos abaixo
// nunca executam (notas §1.5/§1.6).
//
// ASSINATURAS: copiadas literalmente das notas §1.6 (receita do demo). Nada
// além do que a receita usa. ATENÇÃO (R5 do diário): o framework real varia
// entre versões — ex.: createSession com parâmetros extras, descritor de
// openWrite — qualquer divergência só aparece em runtime. Conferir contra os
// AIDL do framework antes de estender.
// ============================================================================

/** §1.6: IPackageManager pm = IPackageManager.Stub.asInterface(binder); */
interface IPackageManager : IInterface {

    /** §1.6: IPackageInstaller installer = pm.getPackageInstaller(); */
    fun getPackageInstaller(): IPackageInstaller =
        throw RuntimeException("stub — framework real prevalece em runtime")

    abstract class Stub : Binder(), IPackageManager {

        companion object {
            /**
             * §1.6: IPackageManager.Stub.asInterface(binder). @JvmStatic para
             * o descritor bater com o método estático real do framework
             * (nunca executa: em runtime prevalece o Stub real).
             */
            @JvmStatic
            fun asInterface(binder: IBinder?): IPackageManager =
                throw RuntimeException("stub — framework real prevalece em runtime")
        }
    }
}

/** §1.6: criada via pm.getPackageInstaller() e usada com SessionParams público. */
interface IPackageInstaller : IInterface {

    /** §1.6: int sessionId = installer.createSession(params); */
    fun createSession(params: PackageInstaller.SessionParams): Int =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** §1.6: IPackageInstallerSession session = installer.openSession(sessionId); */
    fun openSession(sessionId: Int): IPackageInstallerSession =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** Recusa/limpeza abandona a sessão pelo id (notas §2.2). */
    fun abandon(sessionId: Int) =
        throw RuntimeException("stub — framework real prevalece em runtime")
}

/** §1.6: sessão oculta usada no caminho Shizuku (nada de PackageInstaller público). */
interface IPackageInstallerSession : IInterface {

    /** §1.6: OutputStream out = session.openWrite("portix.apk", 0, sizeBytes); */
    fun openWrite(name: String, offsetBytes: Long, lengthBytes: Long): OutputStream =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** §1.6: session.fsync(out) — depois de escrever, antes de fechar. */
    fun fsync(out: OutputStream) =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** §1.6: session.close(); */
    fun close() =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** §1.6: session.commit(statusSender); — ver IntentSenderStub.kt. */
    fun commit(intentSender: IIntentSender) =
        throw RuntimeException("stub — framework real prevalece em runtime")

    /** Recusa/limpeza abandona a própria sessão (notas §2.2). */
    fun abandon() =
        throw RuntimeException("stub — framework real prevalece em runtime")
}
