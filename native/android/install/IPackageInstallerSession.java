/*
 * PORTIX — stub compile-only de hidden API (padrão do demo oficial da
 * Shizuku-API): o Kotlin compila contra ESTE arquivo, mas em runtime o
 * boot classpath prevalece — os corpos nunca executam. Uma interface
 * pública por arquivo (regra do javac).
 */
package android.content.pm;


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
