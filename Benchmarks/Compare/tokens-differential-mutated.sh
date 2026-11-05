#!/bin/sh
# Differential test of the tokenizer on damaged input: N mutated tree-construction inputs and N/5 damaged slices of the real pages, tokenized by AemiHTML and html5ever and diffed token by token.
# A difference that is only a processing instruction against a bogus comment (`<?x>`: AemiHTML keeps the instruction, html5ever follows the standard) is counted apart; any other is a finding.
# Build first: (cd swift && swift build -c release) and (cd rust && cargo build --release).
# usage: tokens-differential-mutated.sh [N] [SEED]
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
count="${1:-100000}"
seed="${2:-1}"
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}"
work="${TMPDIR:-/tmp}/aemihtml-tokens-mutated"
rm -rf "$work"
mkdir -p "$work/in" "$work/out"
python3 "$here/mutate.py" "$cache/tree-construction-src/tree-construction" "$work/in" "$count" "$seed"
python3 "$here/mutate-pages.py" "$work" "$seed" "$((count / 5))"
AEMIHTML_DUMP_DIR="$work/out" "$here/swift/.build/release/CompareHTML" "$work/in" --dump > /dev/null
AEMIHTML_DUMP_DIR="$work/out" "$here/rust/target/release/compare-html-rust" "$work/in" --dump > /dev/null
inputs=0
different=0
other=0
for aemi in "$work/out"/*.aemi.txt; do
    name="${aemi%.aemi.txt}"
    inputs=$((inputs + 1))
    if ! cmp -s "$aemi" "$name.html5ever.txt"; then
        different=$((different + 1))
        if diff "$aemi" "$name.html5ever.txt" | grep '^[<>]' | grep -v -E '^< \?:|^> #:\?' | grep -q .; then
            other=$((other + 1))
            echo "finding: $(basename "$name")"
        fi
    fi
done
echo "inputs $inputs, differing $different, differing otherwise than by a processing instruction: $other"
