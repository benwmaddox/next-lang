// The same service as bench/web/main.nl on tokio: four worker threads, one task per connection, a shared
// direct-mapped cache behind a mutex, and one SQLite connection (behind a mutex) used on cache misses.
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

const SLOTS: usize = 4096;

#[tokio::main(worker_threads = 4)]
async fn main() {
    let listener = TcpListener::bind("0.0.0.0:18084").await.unwrap();
    let cache = Arc::new(Mutex::new(vec![(-1i64, 0i64); SLOTS]));
    let path = std::env::var("NLC_DB").unwrap_or_else(|_| "app.db".into());
    let db = Arc::new(Mutex::new(rusqlite::Connection::open(path).unwrap()));
    loop {
        let Ok((mut stream, _)) = listener.accept().await else { continue };
        stream.set_nodelay(true).ok();
        let cache = cache.clone();
        let db = db.clone();
        tokio::spawn(async move {
            let mut buffer = [0u8; 8192];
            let mut have = 0usize;
            loop {
                let end = loop {
                    if let Some(at) = buffer[..have].windows(4).position(|w| w == b"\r\n\r\n") { break at + 4; }
                    match stream.read(&mut buffer[have..]).await { Ok(0) | Err(_) => return, Ok(n) => have += n }
                };
                let id = buffer[..end].strip_prefix(b"GET /item/").and_then(|rest| {
                    let digits: Vec<u8> = rest.iter().take_while(|b| b.is_ascii_digit()).cloned().collect();
                    std::str::from_utf8(&digits).ok()?.parse::<i64>().ok()
                });
                buffer.copy_within(end..have, 0);
                have -= end;
                let response = match id {
                    Some(key) => {
                        let slot = (key as usize) % SLOTS;
                        let cached = { let c = cache.lock().unwrap(); if c[slot].0 == key { Some(c[slot].1) } else { None } };
                        let value = match cached {
                            Some(v) => v,
                            None => {
                                let v: i64 = db.lock().unwrap()
                                    .prepare_cached("select v from items where id = ?1").unwrap()
                                    .query_row([key], |r| r.get(0)).unwrap_or(-1);
                                cache.lock().unwrap()[slot] = (key, v);
                                v
                            }
                        };
                        let body = format!("{{\"id\":{},\"v\":{}}}", key, value);
                        format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", body.len(), body)
                    }
                    None => "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 21\r\n\r\n{\"error\":\"not found\"}".to_string(),
                };
                if stream.write_all(response.as_bytes()).await.is_err() { return; }
            }
        });
    }
}
