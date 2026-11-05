import AemiHTML
import Foundation

// Tokenizes every page of the directory, `rounds` times after one warm-up; the figure is the best round's thread CPU time. Counts tokens and the bytes of text, so that nothing is optimized away and
// the engines can be checked against each other.
// usage: CompareHTML DIR [--rounds N]
let arguments = CommandLine.arguments
guard arguments.count > 1 else { exit(2) }
let rounds = arguments.firstIndex(of: "--rounds").flatMap { Int(arguments[$0 + 1]) } ?? 7
var loaded: [[UInt8]] = []
for name in ((try? FileManager.default.contentsOfDirectory(atPath: arguments[1])) ?? []).sorted() {
    if let data = FileManager.default.contents(atPath: arguments[1] + "/" + name) { loaded.append(Array(data)) }
}
let pages = loaded
let total = pages.reduce(0) { $0 + $1.count }
func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

func run(collectsErrors: Bool) -> (tokens: Int, text: Int) {
    var tokenCount = 0
    var textBytes = 0
    var options = HTMLTokenizer.Options()
    options.collectsErrors = collectsErrors
    for page in pages {
        let result = HTMLTokenizer.tokenize(page, options: options)
        for token in result.tokens {
            tokenCount += 1
            if token.kind == .text { textBytes += token.text.count }
        }
    }
    return (tokenCount, textBytes)
}

func measure(_ name: String, collectsErrors: Bool) {
    var counts = run(collectsErrors: collectsErrors)
    var best = Double.infinity
    for _ in 0 ..< rounds {
        let start = cpu()
        counts = run(collectsErrors: collectsErrors)
        best = Swift.min(best, cpu() - start)
    }
    print(
        "{\"engine\":\"\(name)\",\"what\":\"tokens\",\"pages\":\(pages.count),\"bytes\":\(total),\"seconds\":\(best),\"mbps\":\(Double(total) / best / 1e6),\"tokens\":\(counts.tokens),\"text_bytes\":\(counts.text)}"
    )
}
func runParse() -> (tokens: Int, text: Int) {
    var nodes = 0
    var textBytes = 0
    for page in pages {
        let document = HTMLParser.parse(page)
        nodes += document.nodeCount
        for node in document.descendants(of: document.root) where document.kind(node) == .text {
            textBytes += document.data(node).count
        }
    }
    return (nodes, textBytes)
}

func measureParse() {
    var counts = runParse()
    var best = Double.infinity
    for _ in 0 ..< rounds {
        let start = cpu()
        counts = runParse()
        best = Swift.min(best, cpu() - start)
    }
    print(
        "{\"engine\":\"aemihtml-parse\",\"what\":\"dom\",\"pages\":\(pages.count),\"bytes\":\(total),\"seconds\":\(best),\"mbps\":\(Double(total) / best / 1e6),\"tokens\":\(counts.tokens),\"text_bytes\":\(counts.text)}"
    )
}
func dumpTokens() {
    func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    func string(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: arguments[1])) ?? []).sorted()
    for (page, name) in zip(pages, names) {
        var lines: [String] = []
        var pending = ""
        func flush() {
            if !pending.isEmpty { lines.append("C:" + escape(pending)) }
            pending = ""
        }
        var options = HTMLTokenizer.Options()
        options.switchesContentModel = true
        for token in HTMLTokenizer.tokenize(page, options: options).tokens {
            switch token.kind {
                case .text: pending += string(token.text)
                case .comment:
                    flush()
                    lines.append("#:" + escape(string(token.text)))
                case .startTag, .endTag:
                    flush()
                    let isStart = token.kind == .startTag
                    let attributes = token.attributes.map { "\(string($0.name))=\(escape(string($0.value)))" }
                        .joined(separator: "\u{1}")
                    lines.append(
                        "\(isStart ? "S" : "E"):\(string(token.name)):\(attributes):\(isStart && token.isSelfClosing ? "/" : "")"
                    )
                case .doctype:
                    flush()
                    lines.append(
                        "D:\(string(token.name)):\(string(token.publicIdentifier)):\(string(token.systemIdentifier))"
                    )
                case .processingInstruction:
                    flush()
                    lines.append("?:\(string(token.name)):\(escape(string(token.data)))")
            }
        }
        flush()
        try? (lines.joined(separator: "\n") + "\n")
            .write(
                toFile: "\(ProcessInfo.processInfo.environment["AEMIHTML_DUMP_DIR"] ?? "/tmp")/\(name).aemi.txt",
                atomically: true,
                encoding: .utf8
            )
    }
}
if arguments.contains("--dump") {
    dumpTokens()
    exit(0)
}
if arguments.contains("--parse") {
    measureParse()
    exit(0)
}
measure("aemihtml", collectsErrors: false)
measure("aemihtml-with-errors", collectsErrors: true)
