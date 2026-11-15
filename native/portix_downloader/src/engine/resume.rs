//! Retomada: estado persistido ao lado do `.part` e validadores fracos.
//!
//! Política de segurança (ver `.ralph/PLAN.md`):
//! - Retomada **só** acontece quando há validador (`ETag` ou `Last-Modified`)
//!   para armar `If-Range`. Sem validador, recomeça do zero — nunca concatena
//!   bytes de arquivos possivelmente diferentes.
//! - Se o servidor responder `200` (arquivo mudou / Range ignorado) ou
//!   `416`, o motor apaga o `.part`/`.meta` e recomeça com segurança.
//! - O formato do `.meta` é `chave=valor` por linha (valores vêm de headers
//!   HTTP, que nunca contêm CR/LF — sem risco de injeção, sem precisar de
//!   parser JSON nem dependência nova).

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use super::fsutil::part_path;

const FORMAT_VERSION: &str = "1";

/// Estado de uma sessão de download interrompida.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResumeMeta {
    pub url: String,
    pub etag: Option<String>,
    pub last_modified: Option<String>,
    pub total: i64,
    pub done: i64,
}

/// Caminho do `.meta` (`<dest>.part.meta`).
pub fn meta_path(dest: &Path) -> PathBuf {
    let mut os = part_path(dest).into_os_string();
    os.push(".meta");
    PathBuf::from(os)
}

impl ResumeMeta {
    /// Metadados para uma sessão nova (zero bytes).
    pub fn fresh(url: &str, total: i64, etag: Option<&str>, last_modified: Option<&str>) -> Self {
        Self {
            url: url.to_string(),
            etag: etag.filter(|v| !v.is_empty()).map(str::to_string),
            last_modified: last_modified.filter(|v| !v.is_empty()).map(str::to_string),
            total,
            done: 0,
        }
    }

    /// Pode retomar? Exige: mesma URL, progresso dentro do intervalo e um
    /// validador para `If-Range`.
    pub fn can_resume(&self, url: &str) -> bool {
        self.url == url
            && self.done > 0
            && self.total > 0
            && self.done < self.total
            && (self.etag.is_some() || self.last_modified.is_some())
    }

    /// Carrega e valida o `.meta`. Arquivo ausente/corrompido → `None`.
    pub fn load(dest: &Path) -> Option<Self> {
        let raw = fs::read_to_string(meta_path(dest)).ok()?;
        let mut url = String::new();
        let mut etag = None;
        let mut last_modified = None;
        let mut total: i64 = -1;
        let mut done: i64 = 0;
        for line in raw.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            match key {
                "v" if value != FORMAT_VERSION => return None,
                "v" => {}
                "url" => url = value.to_string(),
                "etag" => etag = Some(value.to_string()).filter(|v| !v.is_empty()),
                "last_modified" => {
                    last_modified = Some(value.to_string()).filter(|v| !v.is_empty())
                }
                "total" => total = value.parse().ok()?,
                "done" => done = value.parse().ok()?,
                _ => {}
            }
        }
        if url.is_empty() || total < 0 {
            return None;
        }
        Some(Self {
            url,
            etag,
            last_modified,
            total,
            done,
        })
    }

    /// Persiste atomicamente (tmp + rename) para sobreviver a crash no meio.
    pub fn save(&self, dest: &Path) {
        let path = meta_path(dest);
        let tmp = path.with_extension("meta.tmp");
        let body = format!(
            "v={FORMAT_VERSION}\nurl={}\netag={}\nlast_modified={}\ntotal={}\ndone={}\n",
            self.url,
            self.etag.as_deref().unwrap_or(""),
            self.last_modified.as_deref().unwrap_or(""),
            self.total,
            self.done,
        );
        let ok = fs::File::create(&tmp)
            .and_then(|mut f| f.write_all(body.as_bytes()))
            .and_then(|_| fs::rename(&tmp, &path))
            .is_ok();
        if !ok {
            // Meta é otimização, não verdade: falha de escrita não aborta.
            let _ = fs::remove_file(&tmp);
        }
    }

    /// Remove `.meta` e `.meta.tmp` (best-effort).
    pub fn remove(dest: &Path) {
        let path = meta_path(dest);
        let _ = fs::remove_file(&path);
        let mut tmp = path.into_os_string();
        tmp.push(".tmp");
        let _ = fs::remove_file(PathBuf::from(tmp));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("portix-resume-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("mkdir");
        dir
    }

    #[test]
    fn ciclo_save_load_remove() {
        let dir = scratch("ciclo");
        let dest = dir.join("p.apk");
        let meta = ResumeMeta {
            url: "https://x/y.apk".into(),
            etag: Some("\"abc\"".into()),
            last_modified: None,
            total: 1000,
            done: 400,
        };
        meta.save(&dest);
        let loaded = ResumeMeta::load(&dest).expect("meta válida");
        assert_eq!(loaded, meta);
        assert!(loaded.can_resume("https://x/y.apk"));
        assert!(!loaded.can_resume("https://x/outra.apk"));
        ResumeMeta::remove(&dest);
        assert!(ResumeMeta::load(&dest).is_none());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn sem_validador_nao_retoma() {
        let meta = ResumeMeta {
            url: "https://x/y.apk".into(),
            etag: None,
            last_modified: None,
            total: 1000,
            done: 400,
        };
        assert!(!meta.can_resume("https://x/y.apk"));
    }

    #[test]
    fn progresso_fora_do_intervalo_nao_retoma() {
        let base = |done: i64| ResumeMeta {
            url: "u".into(),
            etag: Some("e".into()),
            last_modified: None,
            total: 1000,
            done,
        };
        assert!(!base(0).can_resume("u"));
        assert!(!base(1000).can_resume("u"));
        assert!(!base(1500).can_resume("u"));
        assert!(base(999).can_resume("u"));
    }

    #[test]
    fn meta_corrompida_vira_none() {
        let dir = scratch("corrupt");
        let dest = dir.join("p.apk");
        std::fs::write(meta_path(&dest), b"isto nao e um meta\nv=42\ntotal=abc").unwrap();
        assert!(ResumeMeta::load(&dest).is_none());
        let _ = fs::remove_dir_all(&dir);
    }
}
