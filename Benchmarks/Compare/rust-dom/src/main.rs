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

fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\n', "\\n").replace('\r', "\\r").replace('\t', "\\t") }

// One line per node, as the Swift side writes it. Adjacent text is merged by the DOM already.
fn dump(root: &Handle) -> String {
    let mut lines: Vec<String> = Vec::new();
    let mut stack: Vec<(Handle, usize)> = root.children.borrow().iter().rev().map(|c| (c.clone(), 0)).collect();
    while let Some((node, depth)) = stack.pop() {
        let pad = " ".repeat(depth);
        let mut kids: Vec<Handle> = node.children.borrow().iter().cloned().collect();
        match &node.data {
            NodeData::Element { name, attrs, template_contents, .. } => {
                let space = match &*name.ns { "http://www.w3.org/2000/svg" => "svg", "http://www.w3.org/1998/Math/MathML" => "math", _ => "" };
                let mut a: Vec<String> = attrs.borrow().iter().map(|x| {
                    let prefix = match &*x.name.ns { "http://www.w3.org/1999/xlink" => "xlink ", "http://www.w3.org/XML/1998/namespace" => "xml ", "http://www.w3.org/2000/xmlns/" => if &*x.name.local == "xmlns" { "" } else { "xmlns " }, _ => "" };
                    format!("{}{}={}", prefix, x.name.local, esc(&x.value))
                }).collect();
                a.sort();
                lines.push(format!("{}E {} {} {}", pad, space, name.local, a.join(" \u{1} ")));
                if let Some(contents) = template_contents.borrow().as_ref() {
                    lines.push(format!("{} TC", pad));
                    let mut inner: Vec<(Handle, usize)> = contents.children.borrow().iter().rev().map(|c| (c.clone(), depth + 2)).collect();
                    // Template contents come first, then any ordinary children (there are none in a parsed document).
                    kids.reverse();
                    for k in kids { stack.push((k, depth + 1)); }
                    stack.append(&mut inner);
                    continue;
                }
            }
            NodeData::Text { contents } => lines.push(format!("{}T {}", pad, esc(&contents.borrow()))),
            NodeData::Comment { contents } => lines.push(format!("{}C {}", pad, esc(contents))),
            NodeData::Doctype { name, .. } => lines.push(format!("{}D {}", pad, name)),
            NodeData::ProcessingInstruction { target, .. } => lines.push(format!("{}P {}", pad, target)),
            NodeData::Document => {}
        }
        kids.reverse();
        for k in kids { stack.push((k, depth + 1)); }
    }
    lines.join("\n") + "\n"
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
    if args.iter().any(|a| a == "--tree") {
        let dir = env::var("AEMIHTML_DUMP_DIR").unwrap_or("/tmp".to_string());
        for (page, name) in pages.iter().zip(&names) {
            // Scripting off, as AemiHTML's default: `noscript` content is markup.
            let mut opts = ParseOpts::default();
            opts.tree_builder.scripting_enabled = false;
            let dom = parse_document(RcDom::default(), opts).from_utf8().one(&page[..]);
            fs::write(format!("{}/{}.html5ever.tree.txt", dir, name.file_name().unwrap().to_string_lossy()), dump(&dom.document)).unwrap();
        }
        return;
    }
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
