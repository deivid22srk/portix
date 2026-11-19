package android.content;

/**
 * PORTIX — stub compile-only da hidden API IIntentSender (contrato AIDL real).
 *
 * Existente apenas para o Kotlin compilar chamadas contra a assinatura real;
 * em runtime o boot classpath prevalece (mesma técnica do demo oficial da
 * Shizuku-API). Nunca executa: os corpos lançam RuntimeException.
 */
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
