package android.content

import android.os.Binder
import android.os.IInterface

// ============================================================================
// Stub compile-only de android.content.IIntentSender (classe oculta).
//
// Existe para tipar IPackageInstallerSession.commit (notas §1.6) com o MESMO
// nome qualificado do framework — em runtime a classe real do boot classpath
// prevalece e os corpos nunca executam.
//
// DELIBERADAMENTE SEM MÉTODOS: as assinaturas reais de send/sendIntent
// mudaram entre versões do Android, e um método declarado com descritor
// diferente do framework viraria NoSuchMethodError no binder. A parte 4b
// (ShizukuBridge) decide o formato do sender — local (extendendo este Stub,
// ajustando antes as assinaturas contra o AIDL da API-alvo) ou extraído do
// PendingIntent MUTABLE — e completa este stub conforme necessário (R5).
// ============================================================================

interface IIntentSender : IInterface {

    abstract class Stub : Binder(), IIntentSender
}
