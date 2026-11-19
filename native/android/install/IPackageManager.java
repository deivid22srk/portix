/*
 * PORTIX — stub compile-only de hidden API (padrão do demo oficial da
 * Shizuku-API): o Kotlin compila contra ESTE arquivo, mas em runtime o
 * boot classpath prevalece — os corpos nunca executam. Uma interface
 * pública por arquivo (regra do javac).
 */
package android.content.pm;


public interface IPackageManager extends android.os.IInterface {

    /** AIDL real: pm.getPackageInstaller() para o caminho Shizuku. */
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
