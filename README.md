# AemiHTML

The WHATWG HTML Standard on [Aemi](https://github.com/Aemi-Studio/aemi)'s kernels: a tokenizer, a tree builder, a stream parser, the Encoding Standard's decoders, and extractors that turn a page into Markdown or text. One pass over bytes, no recursion, no failure
(any bytes give a document), no object per token or node. Rebuilt from the archived ADHTML (ask roadmap 0139; ADHTML's source was found on another machine, and `docs/adr/0001` says what was kept and what changed).

```swift
import AemiHTML

// A document, from UTF-8 bytes.
let document = HTMLParser.parse(Array("<p>One<p>Two".utf8))
for node in document.descendants(of: document.root) where document.kind(node) == .element {
    print(String(decoding: document.name(node), as: UTF8.self))
}

// Bytes in any encoding, as a browser would find it (a BOM, the HTTP charset, a <meta>, else UTF-8 or windows-1252).
let page = HTMLParser.parse(encoded: bytes, transportEncoding: "iso-8859-2")
print(page.encoding.name)

// A document that arrives in pieces: the same tree, however it is cut.
var parser = HTMLStreamParser()
for chunk in chunks { parser.feed(chunk) }
let streamed = parser.finish()

// The content of a page, as Markdown.
let extracted = HTMLExtractor.extract(encoded: bytes)
print(extracted.title ?? "", extracted.sections.map(\.content))
```

## What it is

| | |
|---|---|
| `HTMLTokenizer` | The tokenization stage (13.2.5, as the standard reads in 2026, processing instructions included) on a flat tape. |
| `HTMLParser` | Tokenizer and tree builder (13.2.6): all insertion modes, the adoption agency, foster parenting, templates, foreign content, quirks, fragments, `selectedcontent`. Into an arena `HTMLDocument`. |
| `HTMLStreamParser` | The same, fed a piece at a time. The tree is the whole document's at every cut (tested on every cut of every html5lib tokenizer and tree case, on real pages, and on random markup). |
| `HTMLEncodingSniffer`, `HTMLDecoder` | The Encoding Standard: labels, BOM sniffing, the prescan of the first 1024 bytes, the restart when a later `meta` names another encoding; decoders for UTF-16, the 28 single-byte encodings, Shift_JIS, EUC-JP, ISO-2022-JP, GBK, gb18030, Big5 and EUC-KR (generated from the standard's own tables). |
| `HTMLExtractor` | Title, description, content container, sections, Markdown or plain text; chrome and hidden content dropped; nested lists, tables and code languages kept. |

Parse errors are reported by both stages: the tokenizer's with the standard's codes (`HTMLDocument.errors`), the tree builder's by class (`HTMLDocument.treeErrors`, `HTMLTreeError`), each with the offset of its token, when `HTMLParser.Options.collectsErrors` is set.  `HTMLDocument.preorder()` gives the nodes in document order with subtree ends, for scans that sum over subtrees; `HTMLExtractor.densestContainer` uses it to find the main text by text and link density (an option, `fallsBackToTextDensity`, off by default). `HTMLStreamParser(fragmentContext:)` streams a fragment parse, equal to `parseFragment` at every cut of every fragment case. `docs/design/remaining-work.md` has the status, the measurements and the designs.

## How it is built

- **A tape, not a tree.** Tokens are 64-bit slots in one flat array (`TapeSlot` from `AemiKernel`, the layout ADJSON and AemiMarkdown share). Text is a range of the source unless the standard changes it
  (a character reference, a NUL, a name's case); then it is copied once, to a scratch buffer.
- **SIMD where the bytes are plain.** Text, comments, attribute values and script data are scanned with `AemiKernels.firstIndex(inSet:)` for the next byte that matters; the state machine runs only at those.
- **The standard is the test.** `Scripts/fetch-html5lib.sh` fills a cache with [html5lib-tests](https://github.com/html5lib/html5lib-tests) at a pinned commit; the suite runs every tokenizer test, tokens and parse error codes The tree-construction cases come from web-platform-tests, where they have been edited in place since June 2026 (`Scripts/fetch-wpt-tree.sh`, pinned): that copy has the processing-instruction cases (124) and the newer `search`, `template` and `plain-text` ones that html5lib's frozen copy lacks, and every one of its non-scripted cases passes. html5lib's own copy stays the fallback, and the source of the error lists that the error-count check compares with.
  (about 7,000 cases; the processing-instruction states added to the standard in 2026 included; `xmlViolation.test`, which tests an XML-coercion option and not the standard, is not run). Without the cache those tests are disabled, with the reason.
- **Bounded.** Input over 4 GiB is cut there; a tag keeps 4,095 attributes; text slots hold 134 million bytes and longer runs are split. A hostile-input test checks linear time on pathological repeats.

## Speed

`Benchmarks/Compare/run.py` runs 15 real pages (the HTML Standard, Wikipedia, MDN, GitHub, news sites; 19.9 MB, downloaded by `Scripts/fetch-pages.sh`, never committed) through AemiHTML and other parsers, one thread, best of nine rounds of CPU time,

The in-process benchmarks run on [ordo-one's `Benchmark`](https://github.com/ordo-one/benchmark), as AemiJSON's do: percentiles of wall-clock and CPU time, throughput, malloc count and peak memory for tokenizing, parsing, streaming in 16 KiB chunks and extracting, on the smallest, the middle and the largest page and on a synthetic document. The framework is a dependency of the suite alone, and the suite exists only under `AEMIHTML_DEV`, so a package that depends on AemiHTML, and a plain `swift build` or `swift test`, never fetch it:

```sh
AEMIHTML_DEV=1 swift package --allow-writing-to-package-directory benchmark            # all of them
AEMIHTML_DEV=1 swift package benchmark run --filter "parse/.*"                         # a subset
```

`brew install jemalloc` gives the malloc counts; with `BENCHMARK_DISABLE_JEMALLOC=1` the times still run. The comparisons with html5ever, parse5 and Lexbor stay in `Benchmarks/Compare`: they run other languages' programs, which a Swift framework cannot. For a change of a percent or two, the instruction count (`/usr/bin/time -l`) is the instrument; see `docs/design/remaining-work.md`.
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
- `Benchmarks/Compare/tokens-differential-mutated.sh` tokenizes 100,000 mutated html5lib cases and 20,000 damaged slices of the pages with AemiHTML and html5ever and diffs the tokens. The only difference is the processing instruction (`<?x>`), which AemiHTML keeps and the standard makes a bogus comment.
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
