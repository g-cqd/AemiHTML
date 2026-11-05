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
measure("aemihtml", collectsErrors: false)
measure("aemihtml-with-errors", collectsErrors: true)
