/// Writes the nodes of a document, walked in order, as Markdown or plain text: one pass, an explicit stack of line prefixes, lists and inline marks, no recursion. Blocks are separated by one blank line; the first line of a list item
/// carries its marker and the next lines are indented under it; a quote's lines each start with `>`. Inline marks open at the first word inside them and close after the last (`<b> a </b>` is ` **a** `), so no delimiter ever has
/// a space inside it; text is escaped where it would otherwise be Markdown.
struct MarkdownWriter {
    struct Prefix {
        var first: [UInt8]
        var rest: [UInt8]
        var used = false
    }

    struct Mark {
        var opener: [UInt8]
        var closer: [UInt8]
        var written = false
    }

    struct ListState {
        var ordered: Bool
        var next: Int
    }

    let document: HTMLDocument
    let options: HTMLExtractOptions
    let markdown: Bool
    /// Cell mode: nothing is a block, every boundary is a space.
    let inline: Bool

    var out: [UInt8] = []
    var atLineStart = true
    var lineHasContent = false
    var needBlank = false
    var pendingSpace = false
    var prefixes: [Prefix] = []
    var marks: [Mark] = []
    var lists: [ListState] = []
    var previousByte: UInt8 = 0x20
    var digitsAtLineStart = 0
    var skipped = HTMLDocument.Node.none
    var headingDepth = 0
    /// `marks.count` after each link's mark was pushed, so that a closing `a` knows whether it opened one.
    var linkMarks: [Int] = []

    init(document: HTMLDocument, options: HTMLExtractOptions, inline: Bool = false) {
        self.document = document
        self.options = options
        markdown = options.format == .markdown
        self.inline = inline
        out.reserveCapacity(256)
    }

    // MARK: Lines

    /// Ends the current line (trailing spaces trimmed unless it is code).
    mutating func finishLine(raw: Bool = false) {
        guard !atLineStart, !inline else { return }
        if !raw { while out.last == 0x20 { out.removeLast() } }
        out.append(0x0A)
        atLineStart = true
        lineHasContent = false
        pendingSpace = false
        digitsAtLineStart = 0
    }

    /// A block begins or ends: the line ends and a blank line is owed before the next text, unless nothing has been written in the container yet.
    mutating func blockBoundary() {
        if inline {
            pendingSpace = lineHasContent || pendingSpace
            return
        }
        finishLine()
        if prefixes.last?.used ?? true { needBlank = true }
    }

    /// The prefix of the line about to start: the first line of a quote or an item carries its own marker, the lines after it its indent.
    private mutating func emitPrefix() {
        for index in prefixes.indices {
            if prefixes[index].used {
                out.append(contentsOf: prefixes[index].rest)
            } else {
                out.append(contentsOf: prefixes[index].first)
                prefixes[index].used = true
            }
        }
    }

    /// The blank line a block owes, then the prefix: called before any content byte.
    mutating func beginLine() {
        guard atLineStart else { return }
        if needBlank, !out.isEmpty {
            var blank = prefixes.flatMap { $0.used ? $0.rest : [] }
            while blank.last == 0x20 { blank.removeLast() }
            out.append(contentsOf: blank)
            out.append(0x0A)
        }
        needBlank = false
        emitPrefix()
        atLineStart = false
        lineHasContent = false
    }

    mutating func writeRaw(_ bytes: some Sequence<UInt8>) {
        beginLine()
        out.append(contentsOf: bytes)
        lineHasContent = true
        pendingSpace = false
    }

    /// A line of code or of a table, as it is: its own prefix, no escaping, no trimming.
    mutating func writeRawLine(_ bytes: some Sequence<UInt8>) {
        beginLine()
        out.append(contentsOf: bytes)
        finishLine(raw: true)
    }

    // MARK: Inline marks

    mutating func openMark(_ opener: String, _ closer: String) {
        guard markdown else { return }
        marks.append(Mark(opener: Array(opener.utf8), closer: Array(closer.utf8)))
    }

    mutating func closeMark() {
        guard let mark = marks.popLast() else { return }
        if mark.written { out.append(contentsOf: mark.closer) }
    }

    /// The marks that have not been written yet are, now that content comes.
    mutating func flushMarks() {
        guard marks.contains(where: { !$0.written }) else { return }
        beginLine()
        if pendingSpace, lineHasContent {
            out.append(0x20)
            pendingSpace = false
        }
        pendingSpace = false
        for index in marks.indices where !marks[index].written {
            out.append(contentsOf: marks[index].opener)
            marks[index].written = true
            lineHasContent = true
        }
    }

    // MARK: Taking the result

    /// The text so far, trimmed, and the writer ready for the next section.
    mutating func take() -> String {
        finishLine()
        while let last = out.last, last == 0x0A || last == 0x20 { out.removeLast() }
        let text = String(decoding: out, as: UTF8.self)
        out.removeAll(keepingCapacity: true)
        atLineStart = true
        lineHasContent = false
        needBlank = false
        pendingSpace = false
        digitsAtLineStart = 0
        return text
    }
}
