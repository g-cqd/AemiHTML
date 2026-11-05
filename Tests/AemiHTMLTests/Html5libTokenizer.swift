import Foundation

@testable import AemiHTML

/// The tokenizer tests of html5lib (https://github.com/html5lib/html5lib-tests, MIT), read from the cache `Scripts/fetch-html5lib.sh` fills.
enum Html5libTokenizer {
    static var directory: String {
        let cache =
            ProcessInfo.processInfo.environment["AEMIHTML_CORPUS"]
            ?? NSString(string: "~/Library/Caches/AemiHTMLCorpus").expandingTildeInPath
        return cache + "/html5lib-tests/tokenizer"
    }

    static var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".test") }
            .sorted()
    }

    struct Case {
        var file: String
        var description: String
        var input: [UInt8]
        var state: HTMLTokenizer.InitialState
        var lastStartTag: [UInt8]
        var expected: [String]
        var errors: [String]
    }

    /// `\uXXXX` escapes (and pairs) of a test marked `doubleEscaped`; nil if they spell a lone surrogate, which UTF-8 cannot hold.
    static func unescape(_ text: String) -> String? {
        var result = ""
        var units: [UInt16] = []
        func flush() -> Bool {
            guard !units.isEmpty else { return true }
            guard let string = String(utf16CodeUnits: units, count: units.count) as String?,
                string.utf16.elementsEqual(units)
            else { return false }
            result += string
            units = []
            return true
        }
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 5 < scalars.count + 0, scalars[index + 1] == "u",
                let value = UInt16(String(String.UnicodeScalarView(scalars[index + 2 ... index + 5])), radix: 16)
            {
                units.append(value)
                index += 6
            } else {
                if !flush() { return nil }
                result.unicodeScalars.append(scalars[index])
                index += 1
            }
        }
        return flush() ? result : nil
    }

    /// The expected tokens as one line each, characters joined.
    static func normalize(_ output: [Any], escaped: Bool) -> [String]? {
        var lines: [String] = []
        func fix(_ value: Any?) -> String? {
            guard let text = value as? String else { return nil }
            return escaped ? unescape(text) : text
        }
        for item in output {
            guard let token = item as? [Any], let kind = token.first as? String else { continue }
            switch kind {
                case "Character":
                    guard let text = fix(token[1]) else { return nil }
                    if let last = lines.last, last.hasPrefix("C:") {
                        lines[lines.count - 1] = last + text
                    } else {
                        lines.append("C:" + text)
                    }
                case "Comment":
                    guard let text = fix(token[1]) else { return nil }
                    lines.append("#:" + text)
                case "StartTag":
                    guard let name = fix(token[1]), let attributes = token[2] as? [String: Any] else { return nil }
                    var pairs: [String] = []
                    for (key, value) in attributes {
                        guard let k = fix(key), let v = fix(value) else { return nil }
                        pairs.append("\(k)=\(v)")
                    }
                    let closing = token.count > 3 && (token[3] as? Bool) == true ? "/" : ""
                    lines.append("S:\(name):\(pairs.sorted().joined(separator: "\u{1}")):\(closing)")
                case "ProcessingInstruction":
                    guard let target = fix(token[1]), let data = fix(token[2]) else { return nil }
                    lines.append("P:\(target):\(data)")
                case "EndTag":
                    guard let name = fix(token[1]) else { return nil }
                    lines.append("E:" + name)
                case "DOCTYPE" where token.count >= 5:
                    lines.append(
                        "D:\(fix(token[1]) ?? "\u{2}"):\(fix(token[2]) ?? "\u{2}"):\(fix(token[3]) ?? "\u{2}"):\((token[4] as? Bool) == true)"
                    )
                default: return nil
            }
        }
        return lines
    }

    static func cases(in file: String) -> (cases: [Case], skipped: Int) {
        guard let data = FileManager.default.contents(atPath: directory + "/" + file),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tests = root["tests"] as? [[String: Any]]
        else { return ([], 0) }
        var found: [Case] = []
        var skipped = 0
        for test in tests {
            let escaped = (test["doubleEscaped"] as? Bool) == true
            guard var input = test["input"] as? String, let output = test["output"] as? [Any] else { continue }
            if escaped {
                guard let fixed = unescape(input) else {
                    skipped += 1
                    continue
                }
                input = fixed
            }
            guard let expected = normalize(output, escaped: escaped) else {
                skipped += 1
                continue
            }
            var last: [UInt8] = []
            if let name = test["lastStartTag"] as? String { last = Array(name.utf8) }
            let states = (test["initialStates"] as? [String]) ?? ["Data state"]
            let errors = ((test["errors"] as? [[String: Any]]) ?? []).compactMap { $0["code"] as? String }.sorted()
            for name in states {
                let state: HTMLTokenizer.InitialState
                switch name {
                    case "RCDATA state": state = .rcdata
                    case "RAWTEXT state": state = .rawtext
                    case "Script data state": state = .scriptData
                    case "PLAINTEXT state": state = .plaintext
                    case "CDATA section state": state = .cdataSection
                    default: state = .data
                }
                found.append(
                    Case(
                        file: file,
                        description: (test["description"] as? String) ?? "",
                        input: Array(input.utf8),
                        state: state,
                        lastStartTag: last,
                        expected: expected,
                        errors: errors
                    )
                )
            }
        }
        return (found, skipped)
    }

    /// The tokens as the same lines.
    static func lines(_ tokens: HTMLTokens) -> [String] {
        func text(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
        var lines: [String] = []
        for token in tokens.tokens {
            switch token.kind {
                case .text:
                    if let last = lines.last, last.hasPrefix("C:") {
                        lines[lines.count - 1] = last + text(token.text)
                    } else {
                        lines.append("C:" + text(token.text))
                    }
                case .comment: lines.append("#:" + text(token.text))
                case .startTag:
                    let pairs = token.attributes.map { "\(text($0.name))=\(text($0.value))" }
                    lines.append(
                        "S:\(text(token.name)):\(pairs.sorted().joined(separator: "\u{1}")):\(token.isSelfClosing ? "/" : "")"
                    )
                case .endTag: lines.append("E:" + text(token.name))
                case .processingInstruction: lines.append("P:\(text(token.name)):\(text(token.data))")
                case .doctype:
                    let flags = token.doctypeFlags
                    lines.append(
                        "D:\(flags.contains(.hasName) ? text(token.name) : "\u{2}"):\(flags.contains(.hasPublicIdentifier) ? text(token.publicIdentifier) : "\u{2}"):\(flags.contains(.hasSystemIdentifier) ? text(token.systemIdentifier) : "\u{2}"):\(!flags.contains(.forcesQuirks))"
                    )
            }
        }
        return lines
    }

    /// What one case gives: nil if tokens and error codes agree, else a description.
    static func run(_ test: Case, comparesErrors: Bool) -> String? {
        var options = HTMLTokenizer.Options()
        options.initialState = test.state
        options.lastStartTag = test.lastStartTag
        options.switchesContentModel = false
        options.collectsErrors = comparesErrors
        let tokens = HTMLTokenizer.tokenize(test.input, options: options)
        let got = lines(tokens)
        if got != test.expected {
            return
                "\(test.file): \(test.description) [\(test.state)]\n  input    \(String(decoding: test.input, as: UTF8.self).debugDescription)\n  expected \(test.expected)\n  got      \(got)"
        }
        if comparesErrors {
            let codes = tokens.errors.map(\.code.rawValue).sorted()
            if codes != test.errors {
                return
                    "\(test.file): \(test.description) [errors]\n  input    \(String(decoding: test.input, as: UTF8.self).debugDescription)\n  expected \(test.errors)\n  got      \(codes)"
            }
        }
        return nil
    }
}
