// html5ever's full parse into its reference DOM (markup5ever_rcdom): tokenizing and tree construction, the best round's thread CPU time. Counts nodes and the bytes of text.
// usage: compare-html-dom DIR [--rounds N]
use html5ever::driver::ParseOpts;
use html5ever::tendril::TendrilSink;
use html5ever::parse_document;
use markup5ever_rcdom::{Handle, NodeData, RcDom};
use std::{env, fs};

fn cpu() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 / 1e9
}

// An explicit stack: the reference DOM's own Drop is recursive for deep trees, but real pages are not deep.
fn walk(root: &Handle) -> (usize, usize) {
    let (mut nodes, mut text) = (0, 0);
    let mut stack = vec![root.clone()];
    while let Some(node) = stack.pop() {
        nodes += 1;
        if let NodeData::Text { contents } = &node.data { text += contents.borrow().len(); }
        for child in node.children.borrow().iter() { stack.push(child.clone()); }
    }
    (nodes, text)
}

fn run(pages: &[Vec<u8>]) -> (usize, usize) {
    let (mut nodes, mut text) = (0, 0);
    for page in pages {
        let dom = parse_document(RcDom::default(), ParseOpts::default()).from_utf8().one(&page[..]);
        let (n, t) = walk(&dom.document);
        nodes += n;
        text += t;
    }
    (nodes, text)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let rounds = args.iter().position(|a| a == "--rounds").and_then(|i| args.get(i + 1)).and_then(|r| r.parse().ok()).unwrap_or(5);
    let mut names: Vec<_> = fs::read_dir(&args[1]).unwrap().map(|e| e.unwrap().path()).collect();
    names.sort();
    let pages: Vec<Vec<u8>> = names.iter().filter_map(|p| fs::read(p).ok()).collect();
    let total: usize = pages.iter().map(|p| p.len()).sum();
    let mut counts = run(&pages);
    let mut best = f64::INFINITY;
    for _ in 0..rounds {
        let start = cpu();
        counts = run(&pages);
        best = best.min(cpu() - start);
    }
    println!("{{\"engine\":\"html5ever-rcdom\",\"what\":\"dom\",\"pages\":{},\"bytes\":{},\"seconds\":{},\"mbps\":{},\"tokens\":{},\"text_bytes\":{}}}", pages.len(), total, best, total as f64 / best / 1e6, counts.0, counts.1);
}
