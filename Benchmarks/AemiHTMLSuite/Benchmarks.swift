import AemiHTML
import Benchmark
import Foundation

// The project's in-process benchmarks, on ordo-one's `Benchmark` framework: percentiles of wall-clock time, throughput, CPU time, malloc count and peak resident memory.
// Run with `AEMIHTML_DEV=1 swift package benchmark` (add `BENCHMARK_DISABLE_JEMALLOC=1` where jemalloc is not installed: the malloc counts are lost, the times are not).
// The pages are the corpus the comparison harnesses use (`Scripts/fetch-corpus.sh`, in `~/Library/Caches/AemiHTMLCorpus/pages`, or `$AEMIHTML_CORPUS/pages`). Without them
// only the synthetic documents run, and the page benchmarks are not registered. The comparisons with other engines (html5ever, parse5, Lexbor) stay in `Benchmarks/Compare`: they
// run other languages' programs, which this framework cannot.

/// The pages of the corpus, smallest first, as bytes.
private func loadPages() -> [(name: String, bytes: [UInt8])] {
    let root =
        ProcessInfo.processInfo.environment["AEMIHTML_CORPUS"]
        ?? NSString(string: "~/Library/Caches/AemiHTMLCorpus").expandingTildeInPath
    let directory = root + "/pages"
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
    let pages: [(name: String, bytes: [UInt8])] = names.compactMap { name in
        FileManager.default.contents(atPath: directory + "/" + name).map { (name, Array($0)) }
    }
    return pages.sorted { $0.bytes.count < $1.bytes.count }
}

/// A document of `count` list items with links, entities and a table: the same shape at any size, for what no page covers.
private func syntheticDocument(items count: Int) -> [UInt8] {
    var html = "<!DOCTYPE html><html><head><title>Synthetic</title></head><body><ul>"
    for index in 0 ..< count {
        html += "<li class=\"item\"><a href=\"/page/\(index)\">Item &amp; \(index)</a> <em>text</em> &lt;tag&gt;</li>"
    }
    html += "</ul><table>"
    for index in 0 ..< count / 10 { html += "<tr><td>\(index)<td>cell<td>&copy; \(index)" }
    html += "</table></body></html>"
    return Array(html.utf8)
}

nonisolated(unsafe) let benchmarks = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .cpuTotal, .mallocCountTotal, .peakMemoryResident])

    let synthetic = syntheticDocument(items: 5_000)
    Benchmark("tokenize/synthetic") { benchmark in
        for _ in benchmark.scaledIterations { blackHole(HTMLTokenizer.tokenize(synthetic)) }
    }
    Benchmark("parse/synthetic") { benchmark in
        for _ in benchmark.scaledIterations { blackHole(HTMLParser.parse(synthetic)) }
    }

    let pages = loadPages()
    // The smallest, the middle and the largest page: a short document, a typical one, and one that is mostly text and script.
    let chosen = pages.isEmpty ? [] : [pages[0], pages[pages.count / 2], pages[pages.count - 1]]
    for page in chosen {
        let bytes = page.bytes
        Benchmark("tokenize/\(page.name)") { benchmark in
            for _ in benchmark.scaledIterations { blackHole(HTMLTokenizer.tokenize(bytes)) }
        }
        Benchmark("parse/\(page.name)") { benchmark in
            for _ in benchmark.scaledIterations { blackHole(HTMLParser.parse(bytes)) }
        }
        Benchmark("stream 16 KiB chunks/\(page.name)") { benchmark in
            for _ in benchmark.scaledIterations {
                var parser = HTMLStreamParser()
                var offset = 0
                while offset < bytes.count {
                    let end = Swift.min(offset + 16_384, bytes.count)
                    parser.feed(Array(bytes[offset ..< end]))
                    offset = end
                }
                blackHole(parser.finish())
            }
        }
        Benchmark("extract/\(page.name)") { benchmark in
            for _ in benchmark.scaledIterations { blackHole(HTMLExtractor.extract(bytes)) }
        }
    }
    if !pages.isEmpty {
        Benchmark("parse/all pages") { benchmark in
            for _ in benchmark.scaledIterations {
                for page in pages { blackHole(HTMLParser.parse(page.bytes)) }
            }
        }
    }
}
