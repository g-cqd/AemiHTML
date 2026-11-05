#!/usr/bin/env python3
"""Tokenizer throughput: AemiHTML, html5ever (Rust) and Python's html.parser on the pages of `Scripts/fetch-pages.sh`. usage: run.py [--rounds N]
Build first: (cd swift && swift build -c release) and (cd rust && cargo build --release)."""
import json, os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
cache = os.environ.get("AEMIHTML_CORPUS") or os.path.expanduser("~/Library/Caches/AemiHTMLCorpus")
pages = os.path.join(cache, "pages")
rounds = sys.argv[sys.argv.index("--rounds") + 1] if "--rounds" in sys.argv else "7"
commands = [
    [os.path.join(here, "swift/.build/release/CompareHTML"), pages, "--rounds", rounds],
    [os.path.join(here, "swift/.build/release/CompareHTML"), pages, "--rounds", rounds, "--parse"],
    [os.path.join(here, "rust/target/release/compare-html-rust"), pages, "--rounds", rounds],
    [os.path.join(here, "rust-dom/target/release/compare-html-dom"), pages, "--rounds", rounds],
    ["node", os.path.join(here, "node/bench.mjs"), pages, "--rounds", "3"],
    [sys.executable, os.path.join(here, "python/bench.py"), pages, "--rounds", "2"],
    [sys.executable, os.path.join(here, "python/dom.py"), pages, "--rounds", "3"],
]
results = []
for command in commands:
    done = subprocess.run(command, capture_output=True, text=True)
    results += [json.loads(line) for line in done.stdout.splitlines() if line.startswith("{")]
results.sort(key=lambda r: -r["mbps"])
print(f"{results[0]['pages']} pages, {results[0]['bytes'] / 1e6:.1f} MB; load average at the end {os.getloadavg()[0]:.1f}")
for what, title, unit in (("tokens", "Tokenizing only", "Tokens"), ("dom", "Parsing to a DOM (tokenizing and tree construction)", "Nodes")):
    print(f"\n{title}\n\n| Engine | MB/s | {unit} | Text bytes |\n|---|---:|---:|---:|")
    for r in results:
        if r["what"] == what:
            print(f"| {r['engine']} | {r['mbps']:.1f} | {r['tokens']:,} | {r['text_bytes']:,} |")
