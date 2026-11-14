package com.deivid22srk.portix.downloader

import io.flutter.plugin.common.EventChannel

/** Guarda o EventSink atual para o serviço emitir eventos ao Dart. */
object DownloaderBridge {
    @Volatile
    var events: EventChannel.EventSink? = null

    fun emit(event: Map<String, Any?>) {
        events?.success(event)
    }
}
