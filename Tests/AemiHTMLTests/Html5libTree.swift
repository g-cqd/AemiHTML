import Foundation

@testable import AemiHTML

/// The tree-construction tests of html5lib in their `.dat` format, and the tree dump they compare against.
enum Html5libTree {
    private static var cache: String {
        ProcessInfo.processInfo.environment["AEMIHTML_CORPUS"]
            ?? NSString(string: "~/Library/Caches/AemiHTMLCorpus").expandingTildeInPath
    }

    /// html5lib's own copy, frozen in 2026-06 (Scripts/fetch-html5lib.sh): its cases list the errors they expect, which the copy that replaced it mostly does not.
    static var frozenDirectory: String { cache + "/tree-construction-src/tree-construction" }

    /// The copy web-platform-tests keeps (Scripts/fetch-wpt-tree.sh) is the newer one and the one the trees are checked against; the frozen copy is the fallback.
    static var directory: String {
        let wpt = cache + "/wpt-tree-construction"
        return FileManager.default.fileExists(atPath: wpt) ? wpt : frozenDirectory
    }

    /// The `.dat` files of `directory`, but not the `scripted_*` ones: their cases run scripts (`document.write`), which a parser alone cannot.
    static func files(in directory: String = Html5libTree.directory) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".dat") && !$0.hasPrefix("scripted_") }.sorted()
    }

    static var files: [String] { files() }

    /// `file#number` of the cases the standard has moved past (or that need more than parsing), each with the reason: `Tests/AemiHTMLTests/known-differences.txt`.
    static var knownDifferences: [String: String] {
        var found: [String: String] = [:]
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("known-differences.txt").path
        for line in ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n")
        where !line.hasPrefix("#") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2 { found[parts[0]] = parts[1] }
        }
        return found
    }

    struct Case {
        var file: String
        var number: Int
        var data: String
        var fragment: String?
        var scripting: Bool?
        var expected: String
        /// How many errors html5lib lists for the case (its own wording and its own idea of where the standard says one).
        var listedErrors = 0
        var listedLines: [String] = []
        var id: String { "\(file)#\(number)" }
    }

    /// The errors a case lists: the full list is under `#errors`; the newer cases repeat the tokenizer's share of it under `#new-errors` (with positions), and a few new cases list only there.
    private static func listedErrors(in text: String) -> (count: Int, lines: [String]) {
        var lines: [String] = []
        var listedNew = 0
        var section = "#errors"
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") {
                section = String(line)
            } else if !line.isEmpty {
                if section == "#errors" {
                    lines.append(String(line))
                } else if section == "#new-errors" {
                    listedNew += 1
                }
            }
        }
        return (lines.isEmpty ? listedNew : lines.count, lines)
    }

    static func cases(in file: String, from directory: String = Html5libTree.directory) -> [Case] {
        guard let text = try? String(contentsOfFile: directory + "/" + file, encoding: .utf8) else { return [] }
        var found: [Case] = []
        let blocks = text.components(separatedBy: "\n#data\n")
        for (index, block) in blocks.enumerated() {
            var body = block
            if index == 0 {
                guard body.hasPrefix("#data\n") else { continue }
                body = String(body.dropFirst(6))
            }
            guard let errors = body.range(of: "\n#errors\n") else { continue }
            var data = String(body[..<errors.lowerBound])
            var rest = String(body[errors.upperBound...])
            let (listed, lines) = listedErrors(in: rest)
            var fragment: String?
            var scripting: Bool?
            if let range = rest.range(of: "#new-errors\n") { rest = String(rest[range.lowerBound...]) }
            guard let documentMark = rest.range(of: "#document\n") else { continue }
            let header = String(rest[..<documentMark.lowerBound])
            for line in header.split(separator: "\n", omittingEmptySubsequences: false) {
                if line == "#script-on" { scripting = true }
                if line == "#script-off" { scripting = false }
            }
            if let range = header.range(of: "#document-fragment\n") {
                fragment = String(header[range.upperBound...].prefix { $0 != "\n" })
            }
            var expected = String(rest[documentMark.upperBound...])
            // A case may begin with a `#description`, which then trails the case before it in this split.
            if let description = expected.range(of: "\n#description\n") {
                expected = String(expected[..<description.lowerBound])
            }
            if expected.hasPrefix("#description\n") { expected = "" }
            while expected.hasSuffix("\n") { expected.removeLast() }
            if data.hasSuffix("\n") && index == blocks.count - 1 && false { data.removeLast() }
            found.append(
                Case(
                    file: file,
                    number: found.count + 1,
                    data: data,
                    fragment: fragment,
                    scripting: scripting,
                    expected: expected,
                    listedErrors: listed,
                    listedLines: lines
                )
            )
        }
        return found
    }

    /// The dump of the standard's test format.
    static func dump(_ document: HTMLDocument, fragment: Bool) -> String {
        var lines: [String] = []
        func text(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
        let start = fragment ? document.fragmentRoot : document.root
        var depth: [HTMLDocument.Node: Int] = [start: 0]
        for node in document.descendants(of: start) {
            let level = (depth[document.parent(node)] ?? 0) + 1
            depth[node] = level
            let pad = "| " + String(repeating: "  ", count: level - 1)
            switch document.kind(node) {
                case .element:
                    var name = text(document.name(node))
                    switch document.namespace(node) {
                        case .svg: name = "svg " + name
                        case .mathml: name = "math " + name
                        case .html: break
                    }
                    lines.append("\(pad)<\(name)>")
                    let attributes = document.attributes(of: node)
                        .map { attribute -> (String, String) in
                            let prefix = attribute.prefix
                            return ((prefix.isEmpty ? "" : prefix + " ") + text(attribute.name), text(attribute.value))
                        }
                        .sorted { Array($0.0.utf16).lexicographicallyPrecedes(Array($1.0.utf16)) }
                    for (name, value) in attributes { lines.append("\(pad)  \(name)=\"\(value)\"") }
                case .templateContents: lines.append("\(pad)content")
                case .text: lines.append("\(pad)\"\(text(document.data(node)))\"")
                case .comment: lines.append("\(pad)<!-- \(text(document.data(node))) -->")
                case .processingInstruction:
                    // The test format writes the target, a space, the data, and `?>`, whatever the data is (the standard's serialization of a processing instruction).
                    lines.append("\(pad)<?\(text(document.name(node))) \(text(document.data(node)))?>")
                case .doctype:
                    let name = text(document.name(node))
                    let publicID = text(document.publicIdentifier)
                    let systemID = text(document.documentSystemIdentifier)
                    lines.append(
                        publicID.isEmpty && systemID.isEmpty
                            ? "\(pad)<!DOCTYPE \(name)>" : "\(pad)<!DOCTYPE \(name) \"\(publicID)\" \"\(systemID)\">"
                    )
                case .document: break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Runs one case in each scripting mode the case allows; nil if all agree, else what differs.
    static func run(_ test: Case) -> String? {
        for scripting in test.scripting.map({ [$0] }) ?? [false, true] {
            var options = HTMLParser.Options()
            options.scripting = scripting
            let input = Array(test.data.utf8)
            let document: HTMLDocument
            if let context = test.fragment {
                let parts = context.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == "svg" || parts[0] == "math" {
                    document = HTMLParser.parseFragment(
                        input,
                        context: parts[1],
                        namespace: parts[0] == "svg" ? .svg : .mathml,
                        options: options
                    )
                } else {
                    document = HTMLParser.parseFragment(input, context: context, options: options)
                }
            } else {
                document = HTMLParser.parse(input, options: options)
            }
            let got = dump(document, fragment: test.fragment != nil)
            if got != test.expected {
                return
                    "\(test.id) [scripting \(scripting)] \(test.data.debugDescription)\n--- expected\n\(test.expected)\n--- got\n\(got)"
            }
        }
        return nil
    }
}
