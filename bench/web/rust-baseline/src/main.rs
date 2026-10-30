// Same service as bench/web/main.nl in Rust: four blocking worker threads, a shared direct-mapped cache behind a
// mutex, and one SQLite connection per thread. GET /item/<id> -> {"id":..,"v":..}.
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};

const SLOTS: usize = 4096;

fn main() {
    let listener = Arc::new(TcpListener::bind("0.0.0.0:18082").unwrap());
    let cache: Arc<Mutex<Vec<(i64, i64)>>> = Arc::new(Mutex::new(vec![(-1, 0); SLOTS]));
    let path = std::env::var("NLC_DB").unwrap_or_else(|_| "app.db".into());
    let mut handles = Vec::new();
    for _ in 0..4 {
        let listener = listener.clone();
        let cache = cache.clone();
        let path = path.clone();
        handles.push(std::thread::spawn(move || {
            let db = rusqlite::Connection::open(&path).unwrap();
            let mut statement = db.prepare_cached("select v from items where id = ?1").unwrap();
            let mut buffer = [0u8; 8192];
            loop {
                let Ok((mut stream, _)) = listener.accept() else { break };
                stream.set_nodelay(true).ok();
                let mut have = 0usize;
                'connection: loop {
                    let end = loop {
                        if let Some(at) = buffer[..have].windows(4).position(|w| w == b"\r\n\r\n") { break at + 4; }
                        match stream.read(&mut buffer[have..]) { Ok(0) | Err(_) => break 'connection, Ok(n) => have += n }
                    };
                    let head = &buffer[..end];
                    let id = head.strip_prefix(b"GET /item/").and_then(|rest| {
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
                                    let v: i64 = statement.query_row([key], |r| r.get(0)).unwrap_or(-1);
                                    cache.lock().unwrap()[slot] = (key, v);
                                    v
                                }
                            };
                            let body = format!("{{\"id\":{},\"v\":{}}}", key, value);
                            format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", body.len(), body)
                        }
                        None => "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 21\r\n\r\n{\"error\":\"not found\"}".to_string(),
                    };
                    if stream.write_all(response.as_bytes()).is_err() { break; }
                }
            }
        }));
    }
    for h in handles { h.join().ok(); }
}
