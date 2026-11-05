extension MarkdownWriter {
    // MARK: Raw text

    /// The text under `node` as it is written: no collapsing, a `br` a line feed. What is dropped is not in it.
    func rawText(of node: HTMLDocument.Node) -> [UInt8] {
        var text: [UInt8] = []
        var walker = document.walk(node)
        var skip = HTMLDocument.Node.none
        while let event = walker.next() {
            switch event {
                case .enter(let child):
                    if !skip.isNone { continue }
                    switch document.kind(child) {
                        case .text: text.append(contentsOf: document.data(child))
                        case .element:
                            if document.isDropped(child, hidden: options.dropsHiddenContent) {
                                skip = child
                                walker.skipChildren()
                            } else if HTMLName(rawValue: document.atom(child)) == .br {
                                text.append(0x0A)
                            }
                        default: break
                    }
                case .exit(let child): if child == skip { skip = .none }
            }
        }
        return text
    }

    // MARK: Code

    private static func isLanguageByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte == 0x2B || byte == 0x2D || byte == 0x5F
            || byte == 0x23 || byte == 0x2E
    }

    /// The language a code block names: `language-x`, `lang-x` or `highlight-source-x` in a class of the `pre` or its `code`, or `data-lang`.
    func language(of pre: HTMLDocument.Node) -> String {
        func fromClass(_ node: HTMLDocument.Node) -> String? {
            guard let value = document.attribute("class", of: node) else { return nil }
            for word in String(decoding: value, as: UTF8.self)
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            {
                for prefix in ["language-", "lang-", "highlight-source-", "brush:"]
                where word.lowercased().hasPrefix(prefix) {
                    let name = word.dropFirst(prefix.count)
                    if !name.isEmpty { return String(name) }
                }
            }
            return nil
        }
        var found: String?
        var child = document.firstChild(pre)
        while !child.isNone {
            if document.kind(child) == .element, HTMLName(rawValue: document.atom(child)) == .code {
                found = fromClass(child)
            }
            if found != nil { break }
            child = document.nextSibling(child)
        }
        found =
            found ?? fromClass(pre) ?? document.attribute("data-lang", of: pre)
            .map { String(decoding: $0, as: UTF8.self) }
            ?? document.attribute("data-language", of: pre).map { String(decoding: $0, as: UTF8.self) }
        return String(
            (found ?? "").unicodeScalars.prefix(40).filter { $0.isASCII && Self.isLanguageByte(UInt8($0.value)) }
                .map(Character.init)
        )
    }

    mutating func writePre(_ node: HTMLDocument.Node) {
        var text = rawText(of: node)
        while let last = text.last, last == 0x0A || last == 0x0D { text.removeLast() }
        guard text.contains(where: { $0 != 0x0A && $0 != 0x20 && $0 != 0x09 }) else { return }
        blockBoundary()
        var lines = text.split(separator: 0x0A, omittingEmptySubsequences: false)
        while lines.first?.isEmpty == true { lines.removeFirst() }
        if markdown {
            var longest = 0
            var run = 0
            for byte in text {
                run = byte == 0x60 ? run + 1 : 0
                longest = Swift.max(longest, run)
            }
            let fence = [UInt8](repeating: 0x60, count: Swift.max(3, longest + 1))
            writeRawLine(fence + Array(language(of: node).utf8))
            for line in lines { writeRawLine(line) }
            writeRawLine(fence)
        } else {
            for line in lines { writeRawLine(line) }
        }
        blockBoundary()
    }

    mutating func writeInlineCode(_ node: HTMLDocument.Node) {
        let text = String(decoding: rawText(of: node), as: UTF8.self).collapsingWhitespace()
        guard !text.isEmpty else { return }
        guard markdown else {
            writeText(ArraySlice(text.utf8))
            return
        }
        var longest = 0
        var run = 0
        for byte in text.utf8 {
            run = byte == 0x60 ? run + 1 : 0
            longest = Swift.max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        var code = pad + text + pad
        if inline { code = code.replacingScalars(["|": "\\|"]) }
        flushMarks()
        beginLine()
        if pendingSpace, lineHasContent { out.append(0x20) }
        pendingSpace = false
        out.append(contentsOf: Array((fence + code + fence).utf8))
        lineHasContent = true
        previousByte = 0x60
    }

    // MARK: Tables

    /// A table as a GitHub table: its rows, each cell written on a line of its own as inline text (blocks in it become spaces, nested tables are flattened). The first row is the header. Plain text: the rows with ` | ` between cells.
    mutating func writeTable(_ table: HTMLDocument.Node) {
        var rows: [[String]] = []
        var caption = ""
        var depth = 0
        var current: [String]?
        var walker = document.walk(table)
        var skip = HTMLDocument.Node.none
        while let event = walker.next() {
            switch event {
                case .enter(let node):
                    guard skip.isNone, document.kind(node) == .element else { continue }
                    if document.isDropped(node, hidden: options.dropsHiddenContent) {
                        skip = node
                        walker.skipChildren()
                        continue
                    }
                    switch HTMLName(rawValue: document.atom(node)) ?? .unknown {
                        case .table: depth += 1
                        case .tr where depth == 0: current = []
                        case .td where depth == 0, .th where depth == 0:
                            current?.append(cellText(node))
                            if let span = document.attribute("colspan", of: node),
                                let count = Int(String(decoding: span, as: UTF8.self)), count > 1
                            {
                                current?.append(contentsOf: [String](repeating: "", count: Swift.min(count, 100) - 1))
                            }
                            walker.skipChildren()
                        case .caption where depth == 0:
                            caption = cellText(node)
                            walker.skipChildren()
                        default: break
                    }
                case .exit(let node):
                    if node == skip {
                        skip = .none
                        continue
                    }
                    guard document.kind(node) == .element else { continue }
                    switch HTMLName(rawValue: document.atom(node)) ?? .unknown {
                        case .table: depth -= 1
                        case .tr where depth == 0:
                            if let row = current, !row.isEmpty { rows.append(row) }
                            current = nil
                        default: break
                    }
            }
        }
        guard !rows.isEmpty else { return }
        blockBoundary()
        if !caption.isEmpty { writeText(ArraySlice(caption.utf8)) }
        blockBoundary()
        let columns = rows.map(\.count).max() ?? 0
        func line(_ row: [String]) -> String {
            let cells = row + [String](repeating: "", count: columns - row.count)
            return markdown
                ? "| " + cells.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |"
                : cells.joined(separator: " | ")
        }
        writeRawLine(Array(line(rows[0]).utf8))
        if markdown {
            writeRawLine(
                Array(("| " + [String](repeating: "---", count: columns).joined(separator: " | ") + " |").utf8)
            )
        }
        for row in rows.dropFirst() { writeRawLine(Array(line(row).utf8)) }
        blockBoundary()
    }

    /// The text of a cell: its children written inline.
    private func cellText(_ cell: HTMLDocument.Node) -> String {
        var writer = MarkdownWriter(document: document, options: options, inline: true)
        var walker = document.walk(cell)
        while let event = walker.next() { writer.handle(event, &walker) }
        return writer.take()
    }
}
