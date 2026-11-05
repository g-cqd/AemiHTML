# AemiHTML

An HTML tokenizer on [Aemi](https://github.com/Aemi-Studio/aemi)'s kernels: the WHATWG HTML Standard's tokenization stage over UTF-8 bytes, in one pass, with no recursion, no failure (any bytes give tokens) and
no object per token. Promoted from the archived ADHTML (ask roadmap 0139, reopened 2026-11-05); its source could not be recovered, so this is a new build to that roadmap, not a port.

```swift
import AemiHTML

let tokens = HTMLTokenizer.tokenize(Array("<p class=a>Hi &amp; bye".utf8))
for token in tokens.tokens {
    switch token.kind {
        case .startTag: print("<\(String(decoding: token.name, as: UTF8.self))>", token.attributes.count)
        case .text: print(String(decoding: token.text, as: UTF8.self))
        default: break
    }
}
```

## How it is built

- **A tape, not a tree.** Tokens are 64-bit slots in one flat array (`TapeSlot` from `AemiKernel`, the layout ADJSON and AemiMarkdown share). Text is a range of the source unless the standard changes it
  (a character reference, a NUL, a name's case); then it is copied once, to a scratch buffer.
- **SIMD where the bytes are plain.** Text, comments, attribute values and script data are scanned with `AemiKernels.firstIndex(inSet:)` for the next byte that matters; the state machine runs only at those.
- **The standard is the test.** `Scripts/fetch-html5lib.sh` fills a cache with [html5lib-tests](https://github.com/html5lib/html5lib-tests) at a pinned commit; the suite runs every tokenizer test, tokens and parse error codes
  (about 7,000 cases; the processing-instruction states added to the standard in 2026 included; `xmlViolation.test`, which tests an XML-coercion option and not the standard, is not run). Without the cache those tests are disabled, with the reason.
- **Bounded.** Input over 4 GiB is cut there; a tag keeps 4,095 attributes; text slots hold 134 million bytes and longer runs are split. A hostile-input test checks linear time on pathological repeats.

## Speed

`Benchmarks/Compare` runs 15 real pages (the HTML Standard, Wikipedia, MDN, GitHub, news sites; 19.9 MB, downloaded by `Scripts/fetch-pages.sh`, never committed) through AemiHTML and other parsers, one thread, best of nine rounds of CPU
time, Apple M3, at a load average of 3.5:

| Tokenizing only | MB/s | Tokens |
|---|---:|---:|
| **AemiHTML**, errors not collected | **257** | 1,195,936 |
| html5ever 0.35 (Rust; it reports errors, as tokens) | 128 | 1,280,379 |
| **AemiHTML**, errors collected | 170 | 1,195,936 |
| Python `html.parser` (not the HTML5 algorithm) | 7 | 1,195,936 |

| Parsing to a DOM | MB/s | Nodes |
|---|---:|---:|
| **AemiHTML** (the arena `HTMLDocument`) | **157** | 823,420 |
| Lexbor (C, via selectolax) | 100 | 822,696 |
| html5ever with `markup5ever_rcdom` | 82 | 821,916 |
| parse5 7 (JavaScript) | 19 | 822,585 |

The node counts agree to within a fifth of a percent across four independent implementations, which is a check on the tree builder as much as on the benchmark (the differences are whitespace and doctype handling in each library's own DOM).
What it does not say: the DOMs are not the same objects (AemiHTML's text is ranges of the source and its nodes are records in one array; html5ever's are reference-counted nodes with tendrils; Lexbor's are C structs read through Python), the benchmark walks each DOM once to
count nodes and text, and the pages are as served on the day. A run at a load average of 13 gave AemiHTML 65 MB/s (parse) with the others' ordering unchanged: read ratios, not decimals.

Where it comes from (each measured, in this repository's history): the tokenizer allocates nothing per token and the tree builder nothing per node (`AllocationTests` counts, per construct, in release); a run of text is one slot whatever it decodes
to; element names are a `switch` over integers; the document is one array of records, so adding a node is one append; and the scans for the next byte that matters are `AemiKernels`' SIMD search.

## Tree construction

`HTMLParser.parse` runs the tokenizer and the tree builder of 13.2.6 (every insertion mode, the adoption agency algorithm, foster parenting, templates, foreign content, quirks, the fragment parsing algorithm) into an `HTMLDocument`.
It is checked against html5lib's 1,792 tree-construction cases, all but eight (`known-differences.txt`: four from the 2026 processing-instruction change, four that need the `<selectedcontent>` element's own DOM behaviour). The tree's depth is bounded (default 512, as browsers do),
so every pass is linear.

## Not here yet

The HTML-to-Markdown and plain-text extractors ADHTML had: see `docs/roadmap.md`.
