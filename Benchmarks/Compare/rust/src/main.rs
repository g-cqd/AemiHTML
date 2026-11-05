// html5ever's tokenizer (the engine of Servo and Firefox's Rust HTML work), tokens counted by a sink that keeps nothing; the best round's thread CPU time.
// usage: compare-html-rust DIR [--rounds N]
use html5ever::tendril::StrTendril;
use html5ever::tokenizer::states::{Plaintext, Rawtext, Rcdata, ScriptData};
use html5ever::tokenizer::{BufferQueue, Token, TokenSink, TokenSinkResult, Tokenizer, TokenizerOpts};
use html5ever::tokenizer::TagKind;
use std::cell::Cell;
use std::{env, fs};

struct Counter { tokens: Cell<usize>, text: Cell<usize>, dump: bool, lines: std::cell::RefCell<Vec<String>>, pending: std::cell::RefCell<String> }

fn escape(s: &str) -> String { s.replace('\\', "\\\\").replace('\n', "\\n").replace('\r', "\\r").replace('\t', "\\t") }

impl Counter {
    fn flush(&self) {
        let mut pending = self.pending.borrow_mut();
        if !pending.is_empty() { self.lines.borrow_mut().push(format!("C:{}", escape(&pending))); pending.clear(); }
    }
}
impl TokenSink for Counter {
    type Handle = ();
    fn process_token(&self, token: Token, _line: u64) -> TokenSinkResult<()> {
        self.tokens.set(self.tokens.get() + 1);
        if let Token::CharacterTokens(s) = &token { self.text.set(self.text.get() + s.len()); }
        if self.dump {
            match &token {
                Token::CharacterTokens(s) => self.pending.borrow_mut().push_str(s),
                Token::NullCharacterToken => self.pending.borrow_mut().push('\u{0}'),
                Token::ParseError(_) => {}
                other => {
                    self.flush();
                    match other {
                        Token::TagToken(tag) => {
                            let kind = if tag.kind == html5ever::tokenizer::TagKind::StartTag { "S" } else { "E" };
                            let attrs: Vec<String> = tag.attrs.iter().map(|a| format!("{}={}", a.name.local, escape(&a.value))).collect();
                            self.lines.borrow_mut().push(format!("{}:{}:{}:{}", kind, tag.name, attrs.join("\u{1}"), if tag.self_closing && kind == "S" { "/" } else { "" }));
                        }
                        Token::CommentToken(c) => self.lines.borrow_mut().push(format!("#:{}", escape(c))),
                        Token::DoctypeToken(d) => self.lines.borrow_mut().push(format!("D:{}:{}:{}", d.name.as_deref().unwrap_or(""), d.public_id.as_deref().unwrap_or(""), d.system_id.as_deref().unwrap_or(""))),
                        _ => {}
                    }
                }
            }
        }
        // The tree builder's part (13.2.6.2): after these start tags the tokenizer reads text, not markup.
        if let Token::TagToken(tag) = &token {
            if tag.kind == TagKind::StartTag {
                match &*tag.name {
                    "script" => return TokenSinkResult::RawData(ScriptData),
                    "style" | "xmp" | "iframe" | "noembed" | "noframes" => return TokenSinkResult::RawData(Rawtext),
                    "title" | "textarea" => return TokenSinkResult::RawData(Rcdata),
                    "plaintext" => return TokenSinkResult::Plaintext,
                    _ => {}
                }
            }
        }
        TokenSinkResult::Continue
    }
}

fn cpu() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 / 1e9
}

fn run(pages: &[String]) -> (usize, usize) {
    let (mut tokens, mut text) = (0, 0);
    for page in pages {
        let tokenizer = Tokenizer::new(Counter { tokens: Cell::new(0), text: Cell::new(0), dump: false, lines: Default::default(), pending: Default::default() }, TokenizerOpts::default());
        let queue = BufferQueue::default();
        queue.push_back(StrTendril::from_slice(page));
        let _ = tokenizer.feed(&queue);
        tokenizer.end();
        tokens += tokenizer.sink.tokens.get();
        text += tokenizer.sink.text.get();
    }
    (tokens, text)
}

fn dump(pages: &[String], names: &[std::path::PathBuf]) {
    for (page, name) in pages.iter().zip(names) {
        let tokenizer = Tokenizer::new(Counter { tokens: Cell::new(0), text: Cell::new(0), dump: true, lines: Default::default(), pending: Default::default() }, TokenizerOpts::default());
        let queue = BufferQueue::default();
        queue.push_back(StrTendril::from_slice(page));
        let _ = tokenizer.feed(&queue);
        tokenizer.end();
        tokenizer.sink.flush();
        let dir = env::var("AEMIHTML_DUMP_DIR").unwrap_or("/tmp".to_string());
        let out = format!("{}/{}.html5ever.txt", dir, name.file_name().unwrap().to_string_lossy());
        std::fs::write(out, tokenizer.sink.lines.borrow().join("\n") + "\n").unwrap();
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let rounds = args.iter().position(|a| a == "--rounds").and_then(|i| args.get(i + 1)).and_then(|r| r.parse().ok()).unwrap_or(7);
    let mut names: Vec<_> = fs::read_dir(&args[1]).unwrap().map(|e| e.unwrap().path()).collect();
    names.sort();
    let pages: Vec<String> = names.iter().filter_map(|p| fs::read(p).ok()).map(|b| String::from_utf8_lossy(&b).into_owned()).collect();
    if args.iter().any(|a| a == "--dump") { dump(&pages, &names); return; }
    let total: usize = pages.iter().map(|p| p.len()).sum();
    let mut counts = run(&pages);
    let mut best = f64::INFINITY;
    for _ in 0..rounds {
        let start = cpu();
        counts = run(&pages);
        best = best.min(cpu() - start);
    }
    println!("{{\"engine\":\"html5ever\",\"what\":\"tokens\",\"pages\":{},\"bytes\":{},\"seconds\":{},\"mbps\":{},\"tokens\":{},\"text_bytes\":{}}}",
        pages.len(), total, best, total as f64 / best / 1e6, counts.0, counts.1);
}
