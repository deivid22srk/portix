/*
 * PORTIX — stub compile-only de hidden API (padrão do demo oficial da
 * Shizuku-API): o Kotlin compila contra ESTE arquivo, mas em runtime o
 * boot classpath prevalece — os corpos nunca executam. Uma interface
 * pública por arquivo (regra do javac).
 */
package android.content;


public interface IIntentSender extends android.os.IInterface {


    /** Stub AIDL — nunca usado em runtime (framework real prevalece). */
    abstract class Stub extends android.os.Binder implements IIntentSender {

        public static final String DESCRIPTOR = "android.content.IIntentSender";

        public Stub() {
            this.attachInterface(this, DESCRIPTOR);
        }

        public static IIntentSender asInterface(android.os.IBinder binder) {
            throw new RuntimeException("stub — framework real prevalece em runtime");
        }
    }
}
