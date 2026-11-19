/*
 * PORTIX — stub compile-only de hidden API (padrão do demo oficial da
 * Shizuku-API): o Kotlin compila contra ESTE arquivo, mas em runtime o
 * boot classpath prevalece — os corpos nunca executam. Uma interface
 * pública por arquivo (regra do javac).
 */
package android.content.pm;


public interface IPackageInstaller extends android.os.IInterface {

    /** AIDL real (Android 12+ com attributionTag; variantes via reflexão). */
    int createSession(
            android.content.pm.PackageInstaller.SessionParams params,
            String installerPackageName,
            String installerAttributionTag,
            int userId)
            throws android.os.RemoteException;

    IPackageInstallerSession openSession(int sessionId) throws android.os.RemoteException;

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
