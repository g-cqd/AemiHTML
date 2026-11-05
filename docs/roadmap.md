# Roadmap

## Done
- Tokenizer (13.2.5, 2026 text), checked against html5lib's tokenizer tests and, token for token, against html5ever on 15 real pages.
- Tree builder (13.2.6): all insertion modes, adoption agency, foster parenting, templates, foreign content, quirks, fragments; 1,792 html5lib tree tests, eight known differences listed with reasons.
- Arena document (`HTMLDocument`), iterative walks, bounded stack and formatting list, hostile and fuzz tests, allocation tests.
- Extractors to Markdown and plain text, the page API (title, description, container, sections, links, images), read back with AemiMarkdown in tests.
- Benchmarks against Lexbor, html5ever, parse5, `html.parser`.

## Done since (2026-11-05)
- Tree differential against html5ever and parse5 (pages and 100,000 mutated inputs), `selectedcontent`, ill-formed UTF-8, the benchmark at a load of 5. See `docs/design/remaining-work.md`, which also holds the designs and the measurements that changed them.

## Next, in the order the design gives
- Chunked input: feed bytes as they arrive (the tokenizer is resumable; the tree builder's batches are not yet fed across chunk boundaries). A test that every split of a document gives the same tree.
- Encoding sniffing (BOM, `<meta charset>`, prescan) for pages that are not UTF-8.
- Web-platform-tests' tree-construction files (the html5lib copy is frozen).
- `<selectedcontent>`; the tree builder's own parse errors.
- Boilerplate by link density and text density (research, topic 12) as a fallback when a page names no container.
- A preorder tape view of the arena, for scans that do not need links.
- A `fetch` tool in ask on top of `HTMLExtractor` (ask roadmap 0139).
