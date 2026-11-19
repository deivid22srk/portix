package android.content.pm;

/**
 * PORTIX — stubs compile-only das hidden APIs do instalador (contrato AIDL
 * real do Android 14+, mesmo padrão do demo oficial da Shizuku-API).
 *
 * Em runtime o boot classpath prevalece: o Kotlin compila contra ESTES
 * arquivos, mas as classes carregadas são as do framework. Nunca executa:
 * os corpos lançam RuntimeException. Os stubs ficam em JAVA (não Kotlin)
 * porque javac/kotlinc mesclam o pacote java-fonte com o do framework —
 * em Kotlin puro o pacote local sombrearia o android.content.pm inteiro
 * (PreapprovalDetails e companhia viravam "Unresolved reference").
 */
public interface IPackageManager extends android.os.IInterface {

    /** §1.6: IPackageInstaller installer = pm.getPackageInstaller(); */
    IPackageInstaller getPackageInstaller() throws android.os.RemoteException;

    /** Stub AIDL — nunca usado em runtime (framework real prevalece). */
    abstract class Stub extends android.os.Binder implements IPackageManager {

        public static final String DESCRIPTOR = "android.content.pm.IPackageManager";

        public Stub() {
            this.attachInterface(this, DESCRIPTOR);
        }

        public static IPackageManager asInterface(android.os.IBinder binder) {
            throw new RuntimeException("stub — framework real prevalece em runtime");
        }
    }
}

public interface IPackageInstaller extends android.os.IInterface {

    /** AIDL real (Android 12+ com attributionTag; variantes antigas via reflexão). */
    int createSession(
            android.content.pm.PackageInstaller.SessionParams params,
            String installerPackageName,
            String installerAttributionTag,
            int userId)
            throws android.os.RemoteException;

    /** AIDL real: openSession(int). */
    IPackageInstallerSession openSession(int sessionId) throws android.os.RemoteException;

    /** AIDL real: abandonSession(int) — abandono sem abrir a sessão. */
    void abandonSession(int sessionId) throws android.os.RemoteException;

    /** Stub AIDL — nunca usado em runtime (framework real prevalece). */
    abstract class Stub extends android.os.Binder implements IPackageInstaller {

        public static final String DESCRIPTOR = "android.content.pm.IPackageInstaller";

        public Stub() {
            this.attachInterface(this, DESCRIPTOR);
        }

        public static IPackageInstaller asInterface(android.os.IBinder binder) {
            throw new RuntimeException("stub — framework real prevalece em runtime");
        }
    }
}

public interface IPackageInstallerSession extends android.os.IInterface {

    /** AIDL real: openWrite devolve ParcelFileDescriptor transferido pelo binder. */
    android.os.ParcelFileDescriptor openWrite(String name, long offsetBytes, long lengthBytes)
            throws android.os.RemoteException;

    /** AIDL real (Android 14+): commit ganhou forTransferred. */
    void commit(android.content.IIntentSender statusReceiver, boolean forTransferred)
            throws android.os.RemoteException;

    void close() throws android.os.RemoteException;

    void abandon() throws android.os.RemoteException;

    /** Stub AIDL — nunca usado em runtime (framework real prevalece). */
    abstract class Stub extends android.os.Binder implements IPackageInstallerSession {

        public static final String DESCRIPTOR = "android.content.pm.IPackageInstallerSession";

        public Stub() {
            this.attachInterface(this, DESCRIPTOR);
        }

        public static IPackageInstallerSession asInterface(android.os.IBinder binder) {
            throw new RuntimeException("stub — framework real prevalece em runtime");
        }
    }
}
