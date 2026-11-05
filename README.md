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

`Benchmarks/Compare/run.py` runs 15 real pages (the HTML Standard, Wikipedia, MDN, GitHub, news sites; 19.9 MB, downloaded by `Scripts/fetch-pages.sh`, never committed) through AemiHTML and other parsers, one thread, best of nine rounds of CPU time,
Apple M3, at a load average of 5 (the machine is shared; the last run of each table is the one shown):

| Tokenizing only | MB/s | Tokens |
|---|---:|---:|
| **AemiHTML**, errors not collected | **247** | 1,195,936 |
| **AemiHTML**, errors collected | 164 | 1,195,936 |
| html5ever 0.35 (Rust; it reports errors, as tokens) | 125 | 1,280,646 |
| Python `html.parser` (not the HTML5 algorithm) | 15 | 1,195,936 |

| Parsing to a DOM | MB/s | Nodes |
|---|---:|---:|
| **AemiHTML** (the arena `HTMLDocument`) | **150** | 823,420 |
| html5ever with `markup5ever_rcdom` | 81 | 821,916 |
| Lexbor (C, via selectolax) | 76 | 822,696 |
| parse5 7 (JavaScript) | 17 | 822,585 |

**These numbers are comparable because the outputs are equal**, which is checked, not assumed:
- `Benchmarks/Compare/differential.sh` writes each page's tokens as lines, AemiHTML's and html5ever's (whose sink switches the tokenizer into RCDATA, RAWTEXT, script data and PLAINTEXT after the start tags that need it, as the standard requires of a sink), and diffs them: **0 differing lines on all 15 pages**.
- `Benchmarks/Compare/tree-differential.sh` writes the trees AemiHTML, html5ever and parse5 make (scripting off) and diffs them. On the 15 pages AemiHTML's tree equals html5ever's line for line (about 800,000 nodes). On 100,000 inputs made by mutating html5lib's tree-construction cases (seeded), the three agree on 98.3%; of the rest, 1,597 are
  `select` (html5ever and parse5 still follow the "in select" insertion modes that the standard dropped for customizable select; AemiHTML follows the standard and html5lib's current tests), 43 are AemiHTML and html5ever against parse5, 26 AemiHTML and parse5 against html5ever, and **none are AemiHTML against the other two** outside `select`. The cases looked at by hand
  (a stray `</mi>` in a MathML text integration point; `svg` after an unclosed `<a>`, which must reconstruct the formatting element; an LF that a character reference makes after `<pre>`) agree with the standard's text.

What the speed figures do not say: the DOMs are not the same objects (AemiHTML's text is ranges of the source and its nodes are records in one array; html5ever's are reference-counted nodes with tendrils; Lexbor's are C structs read through Python), the benchmark walks each DOM once to count nodes and text, the pages are as served on the day, and
the tokens per page differ by what each library counts as a token. Read ratios, not decimals: a run at a load of 160 and more gave the same ordering and ratio (1.8 to 2.0 for tokenizing).

Where it comes from (each measured, in this repository's history): the tokenizer allocates nothing per token and the tree builder nothing per node (`AllocationTests` counts, per construct, in release); a run of text is one slot whatever it decodes
to; element names are a `switch` over integers; the document is one array of records, so adding a node is one append; and the scans for the next byte that matters are `AemiKernels`' SIMD search.

## Tree construction

`HTMLParser.parse` runs the tokenizer and the tree builder of 13.2.6 (every insertion mode, the adoption agency algorithm, foster parenting, templates, foreign content, quirks, the fragment parsing algorithm) into an `HTMLDocument`.
It is checked against html5lib's 1,792 tree-construction cases, all but eight (`known-differences.txt`: four from the 2026 processing-instruction change, four that need the `<selectedcontent>` element's own DOM behaviour). The tree's depth is bounded (default 512, as browsers do),
so every pass is linear.

## Not here yet

The HTML-to-Markdown and plain-text extractors ADHTML had: see `docs/roadmap.md`.

Extraction (`HTMLExtractor`) over the same 15 pages takes 0.2 s in all (19.9 MB in, 0.8 MB out); the 15.8 MB HTML Standard in one page takes 0.34 s and gives 6.1 MB of Markdown in 24 sections.
