//! Transferência única e correta: stream → `.part` → validar → `rename`.
//!
//! Garantias desta fatia:
//! - **Escrita atômica**: o destino final só aparece via `rename` após
//!   validação (magic APK, tamanho completo, `fsync`). Crash no meio deixa
//!   apenas um `.part`, nunca um APK corrompido com nome final.
//! - **Truncamento detectado**: `done != Content-Length` é erro, não sucesso.
//! - **Pré-checagem de espaço**: compara `Content-Length` com `statvfs`.
//! - **Cancelamento cooperativo**: verificado a cada buffer; cancelar limpa
//!   o `.part`.
//! - **Caminho sanitizado** (defesa em profundidade).

use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use super::error::DownloadError;
use super::fsutil::{io_error, part_path, remove_if_exists, sanitize_destination, usable_space};
use super::http::{map_ureq_error, validate_url};
use super::progress::{ProgressEvent, ProgressTracker};
use super::state::{DownloadState, StateTracker};

/// Magic de ZIP/APK (`PK\x03\x04`).
pub const APK_MAGIC: [u8; 4] = [0x50, 0x4B, 0x03, 0x04];
const BUFFER_SIZE: usize = 64 * 1024;
const MAGIC_LEN: usize = 4;
/// Throttle de emissão de progresso (~10/s — a UI não treme).
const PROGRESS_INTERVAL: Duration = Duration::from_millis(100);
/// Margem de segurança sobre o tamanho remoto na checagem de disco.
const DISK_MARGIN_BYTES: i64 = 1024 * 1024;

/// Resultado de uma transferência concluída.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransferResult {
    pub bytes: i64,
    pub total: i64,
}

/// Executa um download HTTP único de `url` para `dest`.
///
/// Callbacks:
/// - `on_state`: transições (`Connecting`/`Downloading`/`Verifying`/`Completed`).
/// - `on_progress`: amostras throttled com velocidade/ETA.
///
/// Em erro ou cancelamento, o `.part` é removido e o destino final
/// permanece intocado (inclusive um APK bom de um download anterior).
pub fn download(
    agent: &ureq::Agent,
    url: &str,
    dest: &Path,
    cancel: &AtomicBool,
    on_state: &mut dyn FnMut(DownloadState),
    on_progress: &mut dyn FnMut(ProgressEvent),
) -> Result<TransferResult, DownloadError> {
    if cancel.load(Ordering::SeqCst) {
        return Err(DownloadError::Cancelled);
    }
    sanitize_destination(dest)?;
    validate_url(url)?;

    let mut states = StateTracker::new();
    on_state(DownloadState::Connecting);

    let response = agent
        .get(url)
        .set("Accept", "application/vnd.android.package-archive,*/*")
        .call()
        .map_err(map_ureq_error)?;

    let content_type = response
        .header("Content-Type")
        .unwrap_or("")
        .to_ascii_lowercase();
    if content_type.contains("text/html") {
        return Err(DownloadError::NotAnApk("content_type"));
    }

    let total: i64 = response
        .header("Content-Length")
        .and_then(|value| value.trim().parse::<i64>().ok())
        .unwrap_or(-1);

    if total >= 0 {
        if let Some(parent) = dest.parent() {
            if let Some(space) = usable_space(parent) {
                if (space as i64) < total + DISK_MARGIN_BYTES {
                    return Err(DownloadError::DiskFull);
                }
            }
        }
    }

    states
        .transition(DownloadState::Downloading)
        .map_err(|t| DownloadError::Internal(format!("transição inválida {t:?}")))?;
    on_state(DownloadState::Downloading);

    let part = part_path(dest);
    let mut file = File::create(&part).map_err(io_error)?;
    // Pré-alocação esparsa: reduz fragmentação sem custo de escrita.
    if total > 0 {
        let _ = file.set_len(total as u64);
    }

    let mut reader = response.into_reader();
    let mut buffer = vec![0u8; BUFFER_SIZE];
    let mut head = [0u8; MAGIC_LEN];
    let mut head_len = 0usize;
    let mut done: i64 = 0;
    let mut tracker = ProgressTracker::new(PROGRESS_INTERVAL);

    let outcome: Result<(), DownloadError> = loop {
        if cancel.load(Ordering::SeqCst) {
            break Err(DownloadError::Cancelled);
        }
        match reader.read(&mut buffer) {
            Ok(0) => break Ok(()),
            Ok(n) => {
                if head_len < MAGIC_LEN {
                    let take = (MAGIC_LEN - head_len).min(n);
                    head[head_len..head_len + take].copy_from_slice(&buffer[..take]);
                    head_len += take;
                }
                if let Err(e) = file.write_all(&buffer[..n]) {
                    break Err(io_error(e));
                }
                done += n as i64;
                if let Some(event) = tracker.sample(done, total, Instant::now(), false) {
                    on_progress(event);
                }
            }
            Err(e) => break Err(DownloadError::Network(format!("leitura interrompida: {e}"))),
        }
    };

    match outcome {
        Err(error) => {
            drop(file);
            remove_if_exists(&part);
            let _ = states
                .transition(DownloadState::Cancelled)
                .or_else(|_| states.transition(DownloadState::Failed));
            Err(error)
        }
        Ok(()) => {
            states
                .transition(DownloadState::Verifying)
                .map_err(|t| DownloadError::Internal(format!("transição inválida {t:?}")))?;
            on_state(DownloadState::Verifying);

            if let Err(e) = file.sync_all() {
                drop(file);
                remove_if_exists(&part);
                return Err(io_error(e));
            }
            drop(file);

            // Validação de conteúdo (destino .apk exige magic ZIP).
            if is_apk_dest(dest) && (done < MAGIC_LEN as i64 || head != APK_MAGIC) {
                remove_if_exists(&part);
                return Err(DownloadError::NotAnApk("magic"));
            }
            // Validação de completude (truncamento não é sucesso).
            if total >= 0 && done != total {
                remove_if_exists(&part);
                return Err(DownloadError::Truncated { done, total });
            }

            // Concluído: promove o `.part` ao destino final (atômico).
            if let Err(e) = std::fs::rename(&part, dest) {
                remove_if_exists(&part);
                return Err(io_error(e));
            }

            let _ = states.transition(DownloadState::Completed);
            on_state(DownloadState::Completed);
            if let Some(event) = tracker.sample(done, total, Instant::now(), true) {
                on_progress(event);
            }
            Ok(TransferResult { bytes: done, total })
        }
    }
}

fn is_apk_dest(dest: &Path) -> bool {
    dest.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("apk"))
}
