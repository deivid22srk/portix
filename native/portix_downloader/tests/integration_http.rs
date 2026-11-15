//! Testes de integração contra um servidor HTTP local de mentira
//! (`std::net`, zero dependências — ver `.ralph/DECISIONS.md` D6).
//!
//! Cenários desta fatia: 200 completo, truncamento, HTML, não-APK, 404,
//! 500, cancelamento e preservação do APK anterior em caso de falha.
//! Cenários de Range/429/redirect chegam junto com retomada/retry (P1).

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use portix_downloader::engine::error::DownloadError;
use portix_downloader::engine::progress::ProgressEvent;
use portix_downloader::engine::state::DownloadState;
use portix_downloader::engine::{http, transfer};

// ---------------------------------------------------------------------------
// Servidor de mentira
// ---------------------------------------------------------------------------

pub struct MockRequest {
    pub path: String,
    pub headers: Vec<(String, String)>,
}

impl MockRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        let name = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(&name))
            .map(|(_, v)| v.as_str())
    }
}

pub struct MockResponse {
    pub status: u16,
    pub content_type: &'static str,
    pub body: Vec<u8>,
    /// Se definido, responde `Content-Length` maior que o corpo (truncamento).
    pub declared_length: Option<i64>,
    /// Segundos de espera antes de responder (teste de timeout).
    pub delay: Option<Duration>,
}

impl MockResponse {
    fn apk(body: Vec<u8>) -> Self {
        Self {
            status: 200,
            content_type: "application/vnd.android.package-archive",
            body,
            declared_length: None,
            delay: None,
        }
    }
}

pub struct MockServer {
    pub url: String,
    requests: Arc<AtomicUsize>,
    _listener: std::net::SocketAddr,
}

impl MockServer {
    /// Sobe o servidor numa porta efêmera com o handler fixo.
    pub fn start(handler: impl Fn(&MockRequest) -> MockResponse + Send + Sync + 'static) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        let requests = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&requests);
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };
                counter.fetch_add(1, Ordering::SeqCst);
                handle_connection(stream, &handler);
            }
        });
        MockServer {
            url: format!("http://{addr}/app.apk"),
            requests,
            _listener: addr,
        }
    }

    pub fn request_count(&self) -> usize {
        self.requests.load(Ordering::SeqCst)
    }
}

fn handle_connection(mut stream: TcpStream, handler: &dyn Fn(&MockRequest) -> MockResponse) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let Ok(peer) = stream.try_clone() else { return };
    let mut reader = BufReader::new(peer);

    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    let mut parts = request_line.split_whitespace();
    let _method = parts.next().unwrap_or_default();
    let path = parts.next().unwrap_or("/").to_string();

    let mut headers = Vec::new();
    loop {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) if line.trim_end().is_empty() => break,
            Ok(_) => {
                if let Some((k, v)) = line.trim_end().split_once(':') {
                    headers.push((k.trim().to_string(), v.trim().to_string()));
                }
            }
            Err(_) => break,
        }
    }

    let request = MockRequest { path, headers };
    let response = handler(&request);

    if let Some(delay) = response.delay {
        std::thread::sleep(delay);
    }

    let status_text = match response.status {
        200 => "OK",
        206 => "Partial Content",
        404 => "Not Found",
        416 => "Range Not Satisfiable",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        _ => "Status",
    };
    let length = response
        .declared_length
        .unwrap_or(response.body.len() as i64);
    let head = format!(
        "HTTP/1.1 {} {status_text}\r\nContent-Type: {}\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n",
        response.status, response.content_type
    );
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(&response.body);
    let _ = stream.flush();
}

// ---------------------------------------------------------------------------
// Helpers de teste
// ---------------------------------------------------------------------------

fn fake_apk(size: usize) -> Vec<u8> {
    let mut body = vec![0u8; size];
    body[0] = b'P';
    body[1] = b'K';
    body[2] = 0x03;
    body[3] = 0x04;
    for (i, byte) in body.iter_mut().enumerate().skip(4) {
        *byte = (i % 251) as u8;
    }
    body
}

struct ScratchDir(PathBuf);

impl ScratchDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("portix-test-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        ScratchDir(dir)
    }

    fn apk(&self) -> PathBuf {
        self.0.join("portix-1.apk")
    }

    fn part(&self) -> PathBuf {
        self.0.join("portix-1.apk.part")
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn run(
    url: &str,
    dest: &Path,
    cancel: &AtomicBool,
    states: &mut Vec<DownloadState>,
    progress: &mut Vec<ProgressEvent>,
) -> Result<transfer::TransferResult, DownloadError> {
    let agent = http::agent();
    transfer::download(
        &agent,
        url,
        dest,
        cancel,
        &mut |state| states.push(state),
        &mut |event| progress.push(event),
    )
}

static NO_CANCEL: AtomicBool = AtomicBool::new(false);

// ---------------------------------------------------------------------------
// Cenários
// ---------------------------------------------------------------------------

#[test]
fn download_200_completo_promove_rename() {
    let body = fake_apk(256 * 1024);
    let expected = body.clone();
    let server = MockServer::start(move |_| MockResponse::apk(expected.clone()));
    let scratch = ScratchDir::new("ok");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let result = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).expect("ok");

    assert_eq!(result.bytes, 256 * 1024);
    assert_eq!(result.total, 256 * 1024);
    assert_eq!(std::fs::read(&dest).expect("arquivo final"), body);
    assert!(
        !scratch.part().exists(),
        ".part deve ser renomeado, não deixado"
    );
    assert!(states.contains(&DownloadState::Downloading));
    assert!(states.contains(&DownloadState::Verifying));
    assert!(states.contains(&DownloadState::Completed));
    assert!(progress.iter().any(|p| p.speed_bps > 0.0));
}

#[test]
fn stream_truncada_e_erro_e_nao_promove() {
    let body = fake_apk(128 * 1024);
    let server = MockServer::start(move |_| MockResponse {
        // Declara 256 KiB mas manda metade — a conexão caiu "de graça".
        declared_length: Some(256 * 1024),
        ..MockResponse::apk(body.clone())
    });
    let scratch = ScratchDir::new("trunc");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();

    // O ureq detecta corpo fechado antes do total (Network); a checagem
    // própria de `done != Content-Length` (Truncated) é a segunda linha de
    // defesa. Ambos são retentáveis e nunca promovem o arquivo.
    assert!(
        matches!(
            err,
            DownloadError::Truncated { .. } | DownloadError::Network(_)
        ),
        "esperado Truncated/Network, veio {err:?}"
    );
    if let DownloadError::Truncated { done, total } = err {
        assert_eq!(done, 128 * 1024);
        assert_eq!(total, 256 * 1024);
    }
    assert!(err.is_retryable());
    assert!(
        !dest.exists(),
        "destino final não pode aparecer com arquivo truncado"
    );
    assert!(!scratch.part().exists(), ".part limpo após erro");
}

#[test]
fn html_e_rejeitado_por_content_type() {
    let server = MockServer::start(|_| MockResponse {
        status: 200,
        content_type: "text/html; charset=utf-8",
        body: b"<html><body>pagina do telegram</body></html>".to_vec(),
        declared_length: None,
        delay: None,
    });
    let scratch = ScratchDir::new("html");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();
    assert!(
        matches!(err, DownloadError::NotAnApk("content_type")),
        "{err:?}"
    );
    assert!(!dest.exists());
}

#[test]
fn corpo_sem_magic_e_rejeitado() {
    let server = MockServer::start(|_| {
        MockResponse::apk(b"este nao e um zip valido de forma alguma".to_vec())
    });
    let scratch = ScratchDir::new("magic");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();
    assert!(matches!(err, DownloadError::NotAnApk("magic")), "{err:?}");
    assert!(!dest.exists());
}

#[test]
fn http_404_e_fatal_com_codigo_estavel() {
    let server = MockServer::start(|_| MockResponse {
        status: 404,
        content_type: "text/plain",
        body: b"nope".to_vec(),
        declared_length: None,
        delay: None,
    });
    let scratch = ScratchDir::new("404");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();
    assert!(
        matches!(err, DownloadError::Http { status: 404, .. }),
        "{err:?}"
    );
    assert!(!err.is_retryable());
    assert_eq!(err.code(), "http_status");
}

#[test]
fn http_500_e_retentavel() {
    let server = MockServer::start(|_| MockResponse {
        status: 500,
        content_type: "text/plain",
        body: b"boom".to_vec(),
        declared_length: None,
        delay: None,
    });
    let scratch = ScratchDir::new("500");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();
    assert!(
        matches!(err, DownloadError::Http { status: 500, .. }),
        "{err:?}"
    );
    assert!(err.is_retryable());
}

#[test]
fn url_invalida_falha_rapido() {
    let scratch = ScratchDir::new("badurl");
    let dest = scratch.apk();
    let mut states = Vec::new();
    let mut progress = Vec::new();
    for bad in ["", "ftp://x/y.apk", "file:///etc/passwd"] {
        let err = run(bad, &dest, &NO_CANCEL, &mut states, &mut progress).unwrap_err();
        assert_eq!(err.code(), "invalid_url", "{bad}");
    }
}

#[test]
fn cancelamento_limpa_part_e_nao_promove() {
    let body = fake_apk(1024 * 1024);
    let server = MockServer::start(move |_| MockResponse::apk(body.clone()));
    let scratch = ScratchDir::new("cancel");
    let dest = scratch.apk();

    let cancel = AtomicBool::new(true); // já chega cancelado
    let mut states = Vec::new();
    let mut progress = Vec::new();
    let err = run(&server.url, &dest, &cancel, &mut states, &mut progress).unwrap_err();
    assert_eq!(err.code(), "cancelled");
    assert!(!dest.exists());
    assert!(!scratch.part().exists());
    assert_eq!(server.request_count(), 0, "não deve nem abrir conexão");
}

#[test]
fn apk_anterior_sobrevive_a_nova_tentativa_falha() {
    let body = fake_apk(64 * 1024);
    // Primeiro download bom.
    let server_ok = MockServer::start(move |_| MockResponse::apk(body.clone()));
    let scratch = ScratchDir::new("survive");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    run(
        &server_ok.url,
        &dest,
        &NO_CANCEL,
        &mut states,
        &mut progress,
    )
    .expect("primeiro ok");
    let original = std::fs::read(&dest).expect("apk bom");

    // Segunda tentativa contra um servidor quebrado: o destino é intocado.
    let server_bad = MockServer::start(|_| MockResponse {
        status: 404,
        content_type: "text/plain",
        body: b"nope".to_vec(),
        declared_length: None,
        delay: None,
    });
    let err = run(
        &server_bad.url,
        &dest,
        &NO_CANCEL,
        &mut states,
        &mut progress,
    )
    .unwrap_err();
    assert!(matches!(err, DownloadError::Http { status: 404, .. }));
    assert_eq!(std::fs::read(&dest).expect("apk intacto"), original);
}

#[test]
fn progresso_respeita_total_da_resposta() {
    let body = fake_apk(512 * 1024);
    let server = MockServer::start(move |_| MockResponse::apk(body.clone()));
    let scratch = ScratchDir::new("progress");
    let dest = scratch.apk();

    let mut states = Vec::new();
    let mut progress = Vec::new();
    let result = run(&server.url, &dest, &NO_CANCEL, &mut states, &mut progress).expect("ok");
    assert_eq!(result.total, 512 * 1024);
    // Última amostra emitida deve chegar ao total (force no fim).
    let last = progress.last().expect("houve progresso");
    assert_eq!(last.done, result.bytes);
    assert_eq!(last.total, result.total);
}
