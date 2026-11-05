#!/bin/sh
# Differential test of the tree builder: N mutated inputs (seeded) parsed by AemiHTML, html5ever (markup5ever_rcdom) and parse5, scripting off, the trees diffed three ways.
# Build first: (cd swift && swift build -c release), (cd rust-dom && cargo build --release), (cd node && npm install).
# usage: tree-differential.sh [N] [SEED]
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
count="${1:-30000}"
seed="${2:-1}"
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}"
work="${TMPDIR:-/tmp}/aemihtml-tree-differential"
rm -rf "$work"
mkdir -p "$work/in" "$work/out"
python3 "$here/mutate.py" "$cache/tree-construction-src/tree-construction" "$work/in" "$count" "$seed"
AEMIHTML_DUMP_DIR="$work/out" "$here/swift/.build/release/CompareHTML" "$work/in" --tree
AEMIHTML_DUMP_DIR="$work/out" "$here/rust-dom/target/release/compare-html-dom" "$work/in" --tree
AEMIHTML_DUMP_DIR="$work/out" node "$here/node/tree.mjs" "$work/in"
python3 "$here/classify.py" "$work/out" "$work/in"
