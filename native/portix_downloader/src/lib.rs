//! PORTIX — motor de download de APK.
//!
//! Exposto ao Android via JNI. A classe Kotlin `NativeDownloader` chama
//! `startDownload` (assíncrono, roda numa thread própria) e `cancelDownload`.
//! O progresso é reportado de volta ao Kotlin pelo `DownloadCallback`.
//!
//! Assinaturas JNI:
//!   Java_com_deivid22srk_portix_downloader_NativeDownloader_startDownload
//!   Java_com_deivid22srk_portix_downloader_NativeDownloader_cancelDownload

#![allow(non_snake_case)]

use std::collections::HashMap;
use std::io::{Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::sys::jlong;
use jni::{JNIEnv, JavaVM};

static CANCEL_FLAGS: OnceLock<Mutex<HashMap<i64, Arc<AtomicBool>>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<i64>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<i64, Arc<AtomicBool>>> {
    CANCEL_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_id() -> i64 {
    let lock = NEXT_ID.get_or_init(|| Mutex::new(0));
    let mut guard = lock.lock().unwrap();
    *guard += 1;
    *guard
}

fn jstring_to_string(env: &mut JNIEnv, value: &JString) -> String {
    env.get_string(value)
        .map(|text| text.into())
        .unwrap_or_default()
}

fn emit_progress(env: &mut JNIEnv, callback: &GlobalRef, done: i64, total: i64) -> Result<(), String> {
    env.call_method(
        callback.as_obj(),
        "onProgress",
        "(JJ)V",
        &[JValue::Long(done), JValue::Long(total)],
    )
    .map(|_| ())
    .map_err(|error| error.to_string())
}

fn emit_complete(env: &mut JNIEnv, callback: &GlobalRef, ok: bool, error: &str) {
    let text = env.new_string(error).ok();
    let value = match &text {
        Some(handle) => JObject::from(handle.clone()),
        None => JObject::null(),
    };
    let _ = env.call_method(
        callback.as_obj(),
        "onComplete",
        "(ZLjava/lang/String;)V",
        &[JValue::Bool(ok as u8), JValue::Object(&value)],
    );
}

/// Faz o download de `url` para `dest`, reportando progresso pelo callback.
fn transfer(
    env: &mut JNIEnv,
    callback: &GlobalRef,
    url: &str,
    dest: &str,
    cancel: &AtomicBool,
) -> Result<(), String> {
    emit_progress(env, callback, 0, -1)?;

    let response = ureq::get(url)
        .timeout(Duration::from_secs(30))
        .call()
        .map_err(|error| format!("http: {error}"))?;

    let total: i64 = response
        .header("Content-Length")
        .and_then(|value| value.trim().parse::<i64>().ok())
        .unwrap_or(-1);

    let mut reader = response.into_reader();
    let mut file = std::fs::File::create(dest).map_err(|error| format!("file: {error}"))?;

    let mut buffer = vec![0u8; 64 * 1024];
    let mut done: i64 = 0;
    let mut last = Instant::now();

    loop {
        if cancel.load(Ordering::SeqCst) {
            drop(file);
            let _ = std::fs::remove_file(dest);
            return Err("cancelado".to_string());
        }
        let read = reader.read(&mut buffer).map_err(|error| format!("read: {error}"))?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read])
            .map_err(|error| format!("write: {error}"))?;
        done += read as i64;
        if last.elapsed() >= Duration::from_millis(350) {
            emit_progress(env, callback, done, total)?;
            last = Instant::now();
        }
    }

    file.flush().map_err(|error| format!("flush: {error}"))?;
    drop(file);
    emit_progress(env, callback, done, total)?;
    Ok(())
}

fn run_download(jvm: JavaVM, callback: GlobalRef, id: i64, url: String, dest: String, cancel: Arc<AtomicBool>) {
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let mut env = jvm
            .attach_current_thread()
            .map_err(|error| error.to_string())?;
        transfer(&mut env, &callback, &url, &dest, &cancel)
    }));

    let error = match outcome {
        Ok(Ok(())) => None,
        Ok(Err(message)) => Some(message),
        Err(_) => Some("falha interna".to_string()),
    };

    if let Ok(mut env) = jvm.attach_current_thread() {
        emit_complete(&mut env, &callback, error.is_none(), error.as_deref().unwrap_or(""));
    }

    registry().lock().unwrap().remove(&id);
}

#[no_mangle]
pub extern "system" fn Java_com_deivid22srk_portix_downloader_NativeDownloader_startDownload(
    mut env: JNIEnv,
    _class: JClass,
    url: JString,
    dest: JString,
    callback: JObject,
) -> jlong {
    let url = jstring_to_string(&mut env, &url);
    let dest = jstring_to_string(&mut env, &dest);
    if url.is_empty() || dest.is_empty() {
        return 0;
    }

    let jvm = match env.get_java_vm() {
        Ok(vm) => vm,
        Err(_) => return 0,
    };
    let callback = match env.new_global_ref(callback) {
        Ok(reference) => reference,
        Err(_) => return 0,
    };

    let id = next_id();
    let cancel = Arc::new(AtomicBool::new(false));
    registry().lock().unwrap().insert(id, cancel.clone());

    std::thread::spawn(move || run_download(jvm, callback, id, url, dest, cancel));
    id
}

#[no_mangle]
pub extern "system" fn Java_com_deivid22srk_portix_downloader_NativeDownloader_cancelDownload(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if let Some(cancel) = registry().lock().unwrap().get(&handle) {
        cancel.store(true, Ordering::SeqCst);
    }
}
