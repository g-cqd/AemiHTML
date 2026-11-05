/// The parse errors the tree builder finds (WHATWG HTML 13.2.6): a token that the current insertion mode does not allow, an element that was left open, content that had to be moved.
///
/// The standard says "this is a parse error" at about a hundred places in tree construction but gives them no codes, unlike the tokenizer's (`HTMLParseError`). These are classes of those
/// places, named by what went wrong, so a caller can count them, group them, or ignore the ones it does not care about. A conforming document has none, and the builder repairs every one of
/// them in the way the standard says, so an error never changes the tree: they are a report, not a decision.
public enum HTMLTreeError: String, Sendable, CaseIterable {
    // MARK: Doctype

    /// A doctype that is not `<!DOCTYPE html>` (or with the legacy-compat system identifier) came first (13.2.6.4.1).
    case nonConformingDoctype = "non-conforming-doctype"
    /// The document started without a doctype, so it is in quirks mode (13.2.6.4.1).
    case missingDoctype = "missing-doctype"
    /// A doctype where none can be: after the first token. Ignored.
    case unexpectedDoctype = "unexpected-doctype"

    // MARK: Tokens that do not belong where they are

    /// A start tag the insertion mode ignores or handles as a repair: `body` twice, `head` after the head, a table part outside a table, `html` again (its missing attributes are merged).
    case unexpectedStartTag = "unexpected-start-tag"
    /// An end tag with no element to close, in scope or at all, or one the insertion mode ignores; also `</br>`, which is taken for `<br>`, and `</p>` with no `p` open, which opens one.
    case unexpectedEndTag = "unexpected-end-tag"
    /// The input ended while the insertion mode, or an open element that needs an end tag, did not allow it.
    case unexpectedEndOfFile = "unexpected-end-of-file"
    /// Text where only white space may be (after the body, after the frameset, in a head that is closing).
    case unexpectedCharacter = "unexpected-character"
    /// A NUL in content: ignored in the body and in tables, replaced by U+FFFD in foreign content. (The tokenizer reports its own `unexpected-null-character` for the same byte.)
    case unexpectedNullCharacter = "unexpected-null-character-in-content"

    // MARK: Elements that were not closed, or were opened inside themselves

    /// An end tag, or a start tag of `ruby` content, found the current node is not the element it should be after the implied end tags: something was left open and is closed with it.
    case unclosedElement = "unclosed-element"
    /// An element opened where its own kind is still open and may not nest: a form in a form, a heading in a heading, a button in a button, an `a` in an `a`, a `nobr` in a `nobr`, a `table` in a table, a `select` in a `select`.
    case nestedElement = "nested-element"
    /// A formatting element (`a`, `b`, `i`...) was misnested: its end tag found it not on the stack, not in scope, or not the current node (the adoption agency algorithm repairs it).
    case misnestedFormattingElement = "misnested-formatting-element"

    // MARK: Tables

    /// Content a table does not allow (text, or a tag that is not a table part) was moved to before the table (foster parenting, 13.2.6.4.9).
    case fosterParenting = "foster-parenting"

    // MARK: Other repairs

    /// `<image>`, which is taken for `<img>`.
    case imageStartTag = "image-start-tag"
    /// A tag that cannot be in foreign content (SVG or MathML) closed it: an HTML element such as `p` or `div` inside an `svg`.
    case unexpectedHTMLInForeignContent = "unexpected-html-in-foreign-content"
    /// An end tag in foreign content whose name matched no open element of the foreign tree, so it went on to the HTML rules.
    case foreignEndTagMismatch = "foreign-end-tag-mismatch"
}

extension HTMLDocument {
    /// One parse error of the tree builder: its class, and where in the source the token it belongs to starts (nil when the token's text was made by the tokenizer, such as a name with capitals, or is the end of the input).
    public struct TreeError: Sendable, Equatable {
        public var kind: HTMLTreeError
        public var offset: Int?
    }
}
