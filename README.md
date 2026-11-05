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

`Benchmarks/Compare` tokenizes 15 real pages (the HTML Standard, Wikipedia, MDN, GitHub, news sites; 19.9 MB, downloaded by `Scripts/fetch-pages.sh`, never committed) with AemiHTML, html5ever (Rust, the engine of Servo) and
Python's `html.parser`, counting tokens and the bytes of text, one thread, best of seven rounds of CPU time, Apple M3:

| Tokenizer | MB/s | Tokens | Text bytes |
|---|---:|---:|---:|
| AemiHTML, errors not collected | 126.7 | 1,203,730 | 5,751,516 |
| html5ever 0.35 (it always reports errors, as tokens) | 80.7 | 1,280,379 | 5,714,973 |
| AemiHTML, errors collected | 77.9 | 1,203,730 | 5,751,516 |
| Python `html.parser` (not the HTML5 algorithm) | 7.5 | 1,195,936 | 5,751,516 |

Read it as: about 1.6 times html5ever when errors are not wanted, and level with it when they are. html5ever's extra 76,000 tokens are its error tokens. This is one run on a shared machine (a second, at a load average of
13, gave 70, 62 and 59 MB/s: the ordering held, the ratios shrank), on pages as served on the day. The tokenizers do the same job (the standard's tokenization), not the same output: html5ever's text arrives as tendrils and AemiHTML's as ranges of the source.

## Not here yet

Tree construction (the insertion modes) and the HTML-to-Markdown and plain-text extractors ADHTML had: see `docs/roadmap.md`.
