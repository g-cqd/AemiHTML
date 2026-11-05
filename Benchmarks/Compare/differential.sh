#!/bin/sh
# Differential test of the tokenizer: every page of the corpus tokenized by AemiHTML and by html5ever (Rust), both written as one normalized line per token (characters joined; the tag names, attributes, values,
# comments and doctypes as the tokenizers made them), and diffed. Build first: (cd swift && swift build -c release) and (cd rust && cargo build --release).
# usage: differential.sh        (prints each page and the number of lines that differ; 0 for all of them is the result)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
pages="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}/pages"
out="${TMPDIR:-/tmp}/aemihtml-differential"
rm -rf "$out"
mkdir -p "$out"
AEMIHTML_DUMP_DIR="$out" "$here/swift/.build/release/CompareHTML" "$pages" --dump
AEMIHTML_DUMP_DIR="$out" "$here/rust/target/release/compare-html-rust" "$pages" --dump
total=0
for aemi in "$out"/*.aemi.txt; do
    name="$(basename "$aemi" .aemi.txt)"
    lines="$(diff "$aemi" "$out/$name.html5ever.txt" | grep -c '^[<>]' || true)"
    echo "$name $lines"
    total=$((total + lines))
done
echo "total differing lines: $total"
