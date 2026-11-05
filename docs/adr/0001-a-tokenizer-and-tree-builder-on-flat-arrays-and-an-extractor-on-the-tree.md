# 0001: A tokenizer and tree builder on flat arrays, driven together, and an extractor on the tree

**Status:** accepted (2026-11-05). Promotes ADHTML's `Parse/` (archived 2026-10-22; ask roadmap 0139) to Aemi's standards. ADHTML's source was found on a second machine after this package had been started; what follows says what was kept from it and what was changed, from reading it.

## Context

ADHTML was a server-side rendering engine; its parser, about 1,300 lines, was ported from a crawler. It had a byte tokenizer that wrote a tape (a pragmatic one: no RCDATA, RAWTEXT or script data states), a tree builder that was "a pragmatic subset" of the standard
(implied end tags and void elements, no insertion modes, no adoption agency, no tables), a recursive `indirect enum` DOM whose depth was cut at 128 so that its recursive walkers could not overflow, and extractors (`plainText`, `markdown`, `extract`) that walked that tree by recursion and
lost structure (nested lists flattened into one line, tables run together, a code block's language dropped, text not escaped, links inside emphasis flattened to text, every `<header>` removed, hidden text kept).

## Decision

1. **The standard is the specification and its tests are the oracle.** The tokenizer follows 13.2.5 state for state, the tree builder 13.2.6 mode for mode (every insertion mode, the adoption agency algorithm, foster parenting, templates, foreign content, quirks, the fragment algorithm), both
   as the standard reads *now* (it gained processing instructions in 2026, and lost the "in select" modes to customizable select). Checked against html5lib's tokenizer tests (about 7,000 cases, tokens and error codes), its tree-construction tests (1,792 cases, all but eight, each listed with its reason),
   and, independently, against html5ever on real pages (identical token streams on 15 pages, about 1.4 million tokens; the same node counts across four parsers).
2. **Flat arrays, no objects.** Tokens are 64-bit slots on a tape (`TapeSlot`, shared with AemiJSON and AemiMarkdown); text is a range of the source unless the standard changes it, and then it is one contiguous range in a scratch buffer. The document is an arena: one array of node records and one of attribute records,
   linked by index. Nothing is allocated per token or per node, which `AllocationTests` counts per construct in release.
3. **The tree builder drives the tokenizer.** The standard switches the tokenizer's state between tokens (13.2.4): after `script`, `style`, `textarea`; into CDATA in foreign content. So the tokenizer produces a batch (the text before a tag, and the tag), the builder processes it and switches the state, and the
   tokenizer goes on. A document needs no second pass and the two stages share their buffers.
4. **No recursion, bounded work.** Every algorithm is a loop over the explicit stack of open elements and list of active formatting elements; walks of the document are enter/exit events produced from parent and sibling links, with no stack of their own. The stack's depth is bounded (default 512,
   as browsers bound theirs): past it an element is inserted and not opened, and the list of active formatting elements is bounded the same way, which keeps reconstruction linear. Both bounds are deviations from the standard, for documents that nest hundreds deep; the hostile-document tests state them.
5. **Extraction is a pass over the tree, not a second parser.** `HTMLExtractor` finds the title (`og:title`, `<title>`, the first `h1`), the description, the content container (an explicit selector, else `main`, `article`, `[role=main]`, `.content`, `#content`, `#contents`, each only if it holds a fifth of the page's text), and cuts the content
   at `h2` (`h3` if none) into sections, as ADHTML's did; and writes Markdown or plain text. **Changed from ADHTML, on purpose:** nested lists stay nested; tables are tables; a code block carries its language and its fence is longer than any backticks in it; text is escaped where it would be Markdown (checked
   by reading the output back with AemiMarkdown); inline marks open at the first word and close at the last, so no delimiter has a space inside it; headings split sections at any depth; a page's `header` and `footer` go but an article's stay; what a reader cannot see (`hidden`, `aria-hidden`, inline `display:none`)
   is dropped, because the output is read by a model and hidden text is where a page puts instructions for it; links keep only http, https, mailto, tel, fragments and relative references.
6. **Dropped from ADHTML:** the recursive `HTMLNode`, the regex-era `MarkdownNormalize` (replaced by the writer's own line model), the `[Unicode.Scalar]` oracle tokenizer (html5lib's tests and html5ever are the oracle now), and everything that was a server-side rendering engine.

## Consequences

- Faster, measured (README): the tokenizer at about twice html5ever's speed, the parser about 1.6 times Lexbor's, on the same pages and with the same output; and the extraction of a 15 MB page in a third of a second.
- The parse errors the *tree builder* finds are not reported (the tokenizer's are). The html5lib tree tests check the tree, not the error list.
- Selected content (`<selectedcontent>` mirroring the selected option) is DOM behaviour of that element, not parsing, and is not done.
- The tree-construction tests now live in web-platform-tests; the copy pinned here is the last html5lib held (2026-06).
