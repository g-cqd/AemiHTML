# AemiHTML

An HTML tokenizer on [Aemi](https://github.com/Aemi-Studio/aemi)'s kernels: the WHATWG HTML Standard's tokenization stage over UTF-8 bytes, in one pass, with no recursion, no failure (any bytes give tokens) and
no allocation per token. Promoted from the archived ADHTML (ask roadmap 0139, reopened 2026-11-05); its source could not be recovered, so this is a new build to that roadmap, not a port.

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
  (8,000 cases; the processing-instruction states added to the standard in 2026 included). Without the cache those tests are disabled, with the reason.
- **Bounded.** Input over 4 GiB is cut there; a tag keeps 4,095 attributes; text slots hold 134 million bytes and longer runs are split. A hostile-input test checks linear time on pathological repeats.

## Not here yet

Tree construction (the insertion modes) and the HTML-to-Markdown and plain-text extractors ADHTML had: see `docs/roadmap.md`.
