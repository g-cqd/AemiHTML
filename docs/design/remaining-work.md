# Remaining work: designs, and what the measurements changed

Written 2026-11-05 after the differential runs, and updated the same day. Each item says what it is for, the design, the oracle that tells us it is right, and the order.

## Status (end of 2026-11-05)

| Item | State |
|---|---|
| Encodings (labels, BOM, prescan, sniffing, the late-`meta` restart, UTF-16, 28 single-byte, Shift_JIS, EUC-JP, ISO-2022-JP, GBK, gb18030, Big5, EUC-KR) | **Built.** html5lib's 82 encoding cases pass through the whole path; 668 vectors against Python's codecs (one encoding, KOI8-U, differs by the standard's own table); the standard's error rules by hand. |
| Chunked input (`HTMLStreamParser`) | **Built.** Every cut of every html5lib tokenizer case and every non-fragment tree case gives the whole document's tokens, errors and tree; real pages at four chunk sizes; 1,500 random documents. A token larger than the pieces costs linear time. Fragment parsing is not streamed. |
| `selectedcontent`, ill-formed UTF-8, tree differential | Built earlier (see below). |
| Tree-builder parse errors | **Not built.** 117 sites in 13.2.6 and a weak oracle (below). Needs an owner decision on whether the list is wanted. |
| Performance candidates | **Not built**; a better way to measure them was found (below). |
| Boilerplate by link density, preorder tape view, WPT tree files | Not started. |

### What was learned while building these

- **Instructions retired are the measure.** `/usr/bin/time -l` reports them, and they do not move with the machine's load: at a load of 14 to 60 the same binary ran at 55 to 90 MB/s, but its instruction count differed by under 0.5% between runs. Every wall-clock A/B in this file was too noisy to read below 10%. With the count, a change of 1% shows. The streaming support costs 1.6 to 2.3% of a parse's instructions (11.89G to 12.1G over five passes of the 15 pages).
- **Where the instructions are:** tokenizing is 4.3G of the 12.1G (about 720 per token); the tree builder is 7.8G, **about 1,900 per node**, which is a lot. The inclusive profile has `dispatch` at 46%, `insertForeignElement` 9%, `createElement` 7%, `insertCharacters` 6%, `usesForeignRules` 4%, `HTMLName.lookup` 3%, and `memmove` called from `dispatch` at about 8% (a large copy, over 400 bytes, in a per-token path; not found: a debugger breakpoint on `memmove` caught startup noise first, and the next step is a conditional breakpoint inside the parse, or Instruments' Time Profiler with inlined frames).
- **The tokenizer can be streamed without being rewritten** by marking where each token began and undoing a step that touched the end of the input. The cost is one branch where the machine used to treat the end as the end of the document, and the test that finds the places it was missed is "every cut of every case": it found one real bug (a text run extended in place has to be un-extended by the undo) and one design error (a held-back CDATA tail must not split a character).


## Done since the first plan (and measured)

| Item | Result |
|---|---|
| Tree differential | Trees equal html5ever's on all 15 pages (about 800,000 nodes). 100,000 mutated inputs against html5ever and parse5: AemiHTML is never the lone outlier outside `select` (where the standard moved and html5ever and parse5 did not). `Benchmarks/Compare/tree-differential.sh`. |
| `selectedcontent` | Built as a bounded post-parse pass; four known html5lib differences gone; 10 tests; a quadratic cost found by measuring (189 ms to 5 ms) and removed. |
| Ill-formed UTF-8 | The parser's input is decoded as the standard decodes UTF-8 (ill-formed sequences to U+FFFD per maximal subpart, BOM dropped): 0.6% of a parse, no copy when well-formed. |
| Quiet benchmark | Taken at a load of 5: tokenizing 247 against html5ever's 125 MB/s, parsing 150 against 81 (rcdom) and 76 (Lexbor). |
| **Refuted** | "The arrays grow, so sizing them from a count of `<` and `=` will speed the parse." Built, with a SIMD count at 29 GB/s; no measurable difference (A/B, three alternating runs each). Reverted. |

## 1. Performance: where the time is

A quiet-machine profile (`sample`, 10 s of parsing the 15 pages) is flat: the largest self times are the parse loop 14.7%, `memmove` 7.9% (under `dispatch`, array and struct copies), `dispatch` 7.2%, `advance` 5.3%, the SIMD search 4.8%, `nameSlot` + `HTMLName.lookup` 7.1%, and about 7% in retain/release and uniqueness checks. Tokenizing alone is 400 MB/s; the tree builder is two thirds of a parse, at roughly 110 ns per node, which is a lot.

Candidates, each to be tried alone and kept only if an A/B on the same machine shows it (the size-estimate experiment is the warning):
1. **Hash the tag name while scanning it** (the scan already visits each byte to lowercase it), so `HTMLName.lookup` is a table probe, not a second pass: up to 7%.
2. **Records and attribute records through an unsafe mutable buffer** held by the builder for the duration of `run()`, so the uniqueness check and retain/release on every `records[i]` access go: up to 7%.
3. **Find the `memmove` under `dispatch`**: it needs an instruction-level profile (Instruments' Time Profiler with inlined frames, or `perf`-style sampling), not the symbol-level `sample`. Suspects: `BuilderToken` (48 bytes) passed `inout` and copied, `stack.removeLast(n)`/`insert`, list-of-formatting edits.
4. **A fast path in `inBody` for the most common case**: a character token or a plain start tag (`div`, `span`, `a`, `p`, `li`...) with no special rule, which today goes through a `switch` of about 80 names and the foreign-content test first.

Honest expectation: 1 and 2 together might give 10 to 15%. A step change (2x) would need the builder to stop visiting a token through `dispatch`'s generic path, which is a redesign; do it only if a consumer needs it. The extractor, not the parser, is the cost a model-facing tool sees (0.2 s for 20 MB).

## 2. Encodings (built; the design as it was written)

**Why:** real pages are not all UTF-8 (windows-1252, Shift_JIS, GBK, EUC-KR, Big5 are common in the long tail), and the `fetch` tool will meet them. Today non-UTF-8 bytes become U+FFFD.

**Design:** a layer before the parser, `HTMLDecoder`, returning UTF-8 bytes and the encoding used; the tokenizer stays UTF-8 only.
- *Sniffing (13.2.3.1):* a BOM wins; then the transport layer's charset (the caller passes the `Content-Type` charset); then the prescan of the first 1024 bytes (13.2.3.2) for `<meta charset>` and `<meta http-equiv=content-type content=...>`; then UTF-8 (not the locale: ask is not a browser). A `meta` that names UTF-16 means UTF-8; one that names `x-user-defined` means windows-1252.
- *Labels:* the Encoding Standard's label table (about 220 labels to 40 encodings), generated from its `encodings.json`.
- *Decoders, in two phases:* (1) UTF-8, UTF-16LE/BE, and the 28 single-byte encodings (128-entry tables generated from `indexes.json`; windows-1252 is the one that matters); (2) the multi-byte ones: Shift_JIS, EUC-JP, ISO-2022-JP, GBK/GB18030, Big5, EUC-KR, from the standard's index tables stored as a packed blob (not an array literal: a 24,000-entry literal makes the compiler crawl), decoded with the standard's own state machines, including its replacement rules.
- *No Foundation* in the core: Apple's converters differ from the standard in the details (error replacement, windows-31j extensions), and the point is the standard's behavior.
- *The late `meta`:* the standard says to restart the parse if a `meta` after the first 1024 bytes names a different encoding. We do not; the prescan covers the pages that matter, and a restart would be a second parse. Say so in the API docs.

**Oracles:** html5lib's `encoding/` tests (the prescan, about 100 cases, in the cache already); for each single-byte table, all 256 bytes against Python's codec (listing the known WHATWG differences, such as windows-1252's five undefined bytes); for the multi-byte ones, random valid sequences against Python's `shift_jis`/`euc_jp`/`gbk`/`big5hkscs`/`euc_kr`, and the standard's own test files from web-platform-tests (`encoding/` `*.txt`) for the error cases.

**Order:** prescan and labels with the html5lib tests; windows-1252 and UTF-16; the other single-byte tables; the multi-byte ones last.

## 3. The `fetch` tool in ask (roadmap 0139)

**Shape:** a tool `fetch(url, format: markdown|text, selector?, section?)` that downloads, decodes, extracts, and returns the first N KB with the section headings so the model can ask for the next part.

**Decisions that are not about HTML:**
- *Policy:* the sandbox's `network` setting binds commands, not tools that run in ask's own process. The tool must honor it itself: `none` disables it; `localhost` allows loopback only; `provider` refuses it (its host is not the provider's); `any` allows it. Otherwise the sandbox would have a hole that reads like a feature.
- *SSRF:* refuse non-http(s) schemes; resolve the host and refuse loopback, link-local, private and metadata addresses unless the policy is `localhost`/`any` and the user said so; re-check on every redirect (cap 5); no credentials in URLs; cap the body (default 2 MB; the parse is linear, 20 MB is 0.2 s); a total timeout.
- *Content:* `text/html` and `application/xhtml+xml` are extracted; `text/plain`, JSON and Markdown are returned as they are; images and PDFs go to the existing readers or are refused with a reason; everything else is refused.
- *Prompt injection:* the output is wrapped as data from a page, with its URL, and the extractor already drops hidden text, `aria-hidden`, `<script>`, `<template>`, `noscript` content that is hidden, and links with `javascript:` destinations. Say in the tool's description that page text is not instructions. Not a guarantee; a measure.
- *Cache:* none in the first version.

**Oracle:** a local test server in the tests (no external network): redirects, a redirect to a private address, a slow body, an over-cap body, a Latin-1 page with a header charset, a Shift_JIS page with a `meta`.

**Order:** after phase 1 of the encodings (windows-1252 and the prescan are what most pages need).

## 4. Chunked input (built; the design as it was written, with what changed)

What changed in building it: the tokenizer undoes a step by remembering a mark (position, state, tape and scratch and error lengths, and the last tape slot, because a text run is extended in place) at the start of each token; a text state that uses up the input keeps the text and seals the tape, so later text is another slot; the byte preparation (BOM, ill-formed UTF-8, CR LF) carries a held tail between pieces; and the driver waits for half as many bytes again after an undo, which makes a huge token fed a byte at a time linear.


**Value now:** low. The fetch tool caps the body, so it can read it whole and parse once. Chunking would matter for a live preview of a streamed response or for memory on huge inputs. Build it when there is a consumer; keep the design.

**Design:** the tokenizer's source becomes append-only, and `advance()` stops, in the state it is in, whenever a decision needs a byte it does not have yet and the input is not final (it returns "need more"). The places that look ahead: `<!--`, `<!DOCTYPE`, `<![CDATA[` (a fixed prefix), a named character reference (up to 32 bytes, and for attributes the byte after it), the "appropriate end tag" test in RCDATA/RAWTEXT/script data, and CR LF normalization (a trailing CR waits for the next byte). Every other state works byte by byte and keeps its position already. The tree builder already works in batches.
A token that does not complete is re-scanned from its start when more arrives; a 1 GB comment fed in 1-byte chunks would be quadratic, so a state that scans for a stop byte records how far it has scanned (it is a loop over `find(set, from:)` already).
**Oracle:** every split point of every html5lib tokenizer case and of the 15 pages (sampled) gives the same tokens and the same tree as the whole input (E13). **Not started.**

## 5. Parse errors of the tree builder

**What is missing:** the tokenizer's errors are reported with their spec names; the tree builder's are not (about 100 sites in 13.2.6).
**What the measurement says:** against html5lib's expected error lists, the current error count equals html5lib's in 201 of 1,600 cases (12.6%), never above, 1,399 below. But the oracle is weak: html5lib's names (576 of them, in four formats) are its own, the standard gives the tree builder's errors no codes, and html5lib counts at its own granularity (one error per character *run* foster-parented, not per code point). Exact parity is not a well-defined target.
**Recommendation:** do not chase html5lib's counts. If an error list is wanted (a linter, a "this page is malformed" signal), add `HTMLParseError` cases for the tree builder's classes (`unexpectedDoctype`, `unexpectedStartTag`, `unexpectedEndTag`, `misnestedFormatting`, `fosterParented`, `unclosedAtEndOfFile`, `missingDoctype`...), reported at each of the standard's sites, with the offset of the token; tested by one hand-written case per site, and with html5lib's counts used only as a smoke test (a case with zero expected errors must give zero). **Decision for the owner:** is a tree-builder error list wanted? Nobody consumes it today.

## 6. Other items from the roadmap

- **Boilerplate by link density** (research topic 12): a fallback when a page names no container. Build with a corpus of 15 pages and hand-marked main content; measure recall of text. Not started.
- **Preorder tape view of the arena** (for scans that do not need links): only if a consumer's scan is measurably slower on the linked arena. Not started.
- **WPT tree-construction files:** the html5lib copy is frozen (2026-06); WPT's `html/syntax/parsing/` has the live ones. Fetch script and a second pinned commit. Cheap; do it with the next standards bump.
- **Late `meta` restart, `isindex`:** `isindex` is not special in the current standard and html5ever treats it as if it were; AemiHTML follows the standard.
