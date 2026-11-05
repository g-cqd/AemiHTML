// html5ever's tokenizer (the engine of Servo and Firefox's Rust HTML work), tokens counted by a sink that keeps nothing; the best round's thread CPU time.
// usage: compare-html-rust DIR [--rounds N]
use html5ever::tendril::StrTendril;
use html5ever::tokenizer::{BufferQueue, Token, TokenSink, TokenSinkResult, Tokenizer, TokenizerOpts};
use std::cell::Cell;
use std::{env, fs};

struct Counter { tokens: Cell<usize>, text: Cell<usize> }
impl TokenSink for Counter {
    type Handle = ();
    fn process_token(&self, token: Token, _line: u64) -> TokenSinkResult<()> {
        self.tokens.set(self.tokens.get() + 1);
        if let Token::CharacterTokens(s) = &token { self.text.set(self.text.get() + s.len()); }
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
        let tokenizer = Tokenizer::new(Counter { tokens: Cell::new(0), text: Cell::new(0) }, TokenizerOpts::default());
        let queue = BufferQueue::default();
        queue.push_back(StrTendril::from_slice(page));
        let _ = tokenizer.feed(&queue);
        tokenizer.end();
        tokens += tokenizer.sink.tokens.get();
        text += tokenizer.sink.text.get();
    }
    (tokens, text)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let rounds = args.iter().position(|a| a == "--rounds").and_then(|i| args.get(i + 1)).and_then(|r| r.parse().ok()).unwrap_or(7);
    let mut names: Vec<_> = fs::read_dir(&args[1]).unwrap().map(|e| e.unwrap().path()).collect();
    names.sort();
    let pages: Vec<String> = names.iter().filter_map(|p| fs::read(p).ok()).map(|b| String::from_utf8_lossy(&b).into_owned()).collect();
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
