# AemiHTML roadmap

Done: the tokenizer (`HTMLTokenizer`), checked against html5lib's tokenizer tests, tokens and error codes; a tape of tokens (`HTMLTokens`); the named and numeric character references; processing instructions.

Next, in this order, each with its own measure before it is called done:

1. **Tree construction** (13.2.6): the insertion modes and the adoption agency algorithm, on an explicit stack, into a tape DOM (a preorder `[UInt64]` with the subtree's end in a container's `low`, as `TapeSlot` documents,
   which is the layout ADHTML's `HTMLTape` had). Checked against the tree-construction tests, which html5lib no longer keeps: they are maintained in web-platform-tests (`html/syntax/parsing`, per html5lib-tests' README), so the fetch script gains that source and a pinned commit; the case count is to be measured then. The recursive `HTMLNode` walk of ADHTML does not come back.
2. **Extractors**: HTML to plain text and to Markdown (headings, paragraphs, lists, links, code, tables, emphasis; scripts, styles, navigation and hidden elements dropped), which is the consumer roadmap 0139 waited for (a fetch tool for ask).
   Round trip as a test: the Markdown AemiMarkdown parses to the structure the HTML had.
3. **Streaming**: feed the tokenizer in chunks (a fetched page arrives that way); the state machine already keeps all its state in `HTMLTokenizer`, the open question is a token that spans two chunks.
4. **Encoding sniffing** (13.2.3.2): BOM, `<meta charset>`, windows-1252 as the default; today the input is UTF-8.
5. **AemiMarkdown's HTML**: its inline-HTML and HTML-block scanners are hand-written to CommonMark 4.6 and 6.6, and need not change; this package is for a consumer that needs the tree.
6. **Research queue**: `g-cqd/research` has the notes on SIMD tokenization (Mytkowicz et al., Langdale and Lemire) that bear on the tokenizer's next 2x.
