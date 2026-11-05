import Foundation

@testable import AemiHTML

/// The tree-construction tests of html5lib in their `.dat` format, and the tree dump they compare against.
enum Html5libTree {
    static var directory: String {
        let cache =
            ProcessInfo.processInfo.environment["AEMIHTML_CORPUS"]
            ?? NSString(string: "~/Library/Caches/AemiHTMLCorpus").expandingTildeInPath
        return cache + "/tree-construction-src/tree-construction"
    }

    static var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".dat") }
            .sorted()
    }

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
        var id: String { "\(file)#\(number)" }
    }

    static func cases(in file: String) -> [Case] {
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
            while expected.hasSuffix("\n") { expected.removeLast() }
            if data.hasSuffix("\n") && index == blocks.count - 1 && false { data.removeLast() }
            found.append(
                Case(
                    file: file,
                    number: found.count + 1,
                    data: data,
                    fragment: fragment,
                    scripting: scripting,
                    expected: expected
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
                    let data = text(document.data(node))
                    lines.append("\(pad)<?\(text(document.name(node)))\(data.isEmpty ? "" : " " + data)>")
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
