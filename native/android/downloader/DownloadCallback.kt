package com.deivid22srk.portix.downloader

/** Callback chamado pelo motor Rust numa thread própria. */
interface DownloadCallback {
    fun onProgress(done: Long, total: Long)
    fun onComplete(ok: Boolean, error: String?)
}
