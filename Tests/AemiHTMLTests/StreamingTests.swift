import Foundation
import Testing

@testable import AemiHTML

/// A stream is cut anywhere and the tokens, the errors and the tree are the whole input's.
@Suite("Chunked input", .enabled(if: !Html5libTokenizer.files.isEmpty, "run Scripts/fetch-html5lib.sh"))
struct StreamingTests {
    private static func options(for test: Html5libTokenizer.Case, errors: Bool) -> HTMLTokenizer.Options {
        var options = HTMLTokenizer.Options()
        options.initialState = test.state
        options.lastStartTag = test.lastStartTag
        options.switchesContentModel = false
        options.collectsErrors = errors
        return options
    }

    @Test(arguments: Html5libTokenizer.files)
    func `every cut of every tokenizer case gives the tokens of the whole`(file: String) {
        var failures: [String] = []
        var runs = 0
        for test in Html5libTokenizer.cases(in: file).cases {
            let options = Self.options(for: test, errors: true)
            let whole = HTMLTokenizer.tokenize(test.input, options: options)
            let wanted = Html5libTokenizer.lines(whole)
            let wantedErrors = whole.errors.map(\.code.rawValue).sorted()
            // Cut in two at every offset, and in single bytes.
            var cutSets = (1 ..< Swift.max(1, test.input.count)).map { [$0] }
            cutSets.append(Array(1 ..< Swift.max(1, test.input.count)))
            for cuts in cutSets {
                runs += 1
                let streamed = HTMLTokenizer.tokenizeStreaming(test.input, options: options, cuts: cuts)
                let got = Html5libTokenizer.lines(streamed)
                let gotErrors = streamed.errors.map(\.code.rawValue).sorted()
                if got != wanted || gotErrors != wantedErrors {
                    failures.append(
                        "\(test.description) [\(test.state)] cut \(cuts.prefix(3))\n  input \(String(decoding: test.input, as: UTF8.self).debugDescription)\n  whole \(wanted) \(wantedErrors)\n  cut   \(got) \(gotErrors)"
                    )
                    break
                }
            }
        }
        #expect(
            failures.isEmpty,
            Comment(rawValue: "\(failures.count) in \(file)\n" + failures.prefix(5).joined(separator: "\n"))
        )
        #expect(runs > 0 || Html5libTokenizer.cases(in: file).cases.isEmpty)
    }
}

@Suite("Chunked input, the tree", .enabled(if: !Html5libTree.files.isEmpty, "run Scripts/fetch-html5lib.sh"))
struct StreamingTreeTests {
    private func streamed(_ data: [UInt8], cuts: [Int], scripting: Bool) -> HTMLDocument {
        var options = HTMLParser.Options()
        options.scripting = scripting
        var parser = HTMLStreamParser(options: options)
        var start = 0
        for cut in cuts + [data.count] where cut > start && cut <= data.count {
            parser.feed(Array(data[start ..< cut]))
            start = cut
        }
        return parser.finish()
    }

    @Test(arguments: Html5libTree.files)
    func `every cut of every tree-construction case gives the tree of the whole`(file: String) {
        let known = Html5libTree.knownDifferences
        var failures: [String] = []
        for test in Html5libTree.cases(in: file) where test.fragment == nil && known[test.id] == nil {
            let data = Array(test.data.utf8)
            for scripting in test.scripting.map({ [$0] }) ?? [false, true] {
                var cutSets = (1 ..< Swift.max(1, data.count)).map { [$0] }
                cutSets.append(Array(1 ..< Swift.max(1, data.count)))
                for cuts in cutSets {
                    let got = Html5libTree.dump(streamed(data, cuts: cuts, scripting: scripting), fragment: false)
                    if got != test.expected {
                        failures.append(
                            "\(test.id) [scripting \(scripting)] cut \(cuts.prefix(3)) \(test.data.debugDescription)\n--- expected\n\(test.expected)\n--- got\n\(got)"
                        )
                        break
                    }
                }
            }
        }
        #expect(
            failures.isEmpty,
            Comment(rawValue: "\(failures.count) in \(file)\n" + failures.prefix(3).joined(separator: "\n"))
        )
    }
}

@Suite("Chunked input, pages and fuzz")
struct StreamingPageTests {
    private func parsed(_ data: [UInt8], pieces: [[UInt8]], options: HTMLParser.Options = HTMLParser.Options())
        -> HTMLDocument
    {
        var parser = HTMLStreamParser(options: options)
        for piece in pieces { parser.feed(piece) }
        return parser.finish()
    }

    private func chunks(_ data: [UInt8], every size: Int) -> [[UInt8]] {
        stride(from: 0, to: data.count, by: size).map { Array(data[$0 ..< Swift.min($0 + size, data.count)]) }
    }

    @Test(arguments: [1_000, 4_096, 7_777, 65_536])
    func `a real page in pieces of one size gives its tree`(size: Int) throws {
        let directory = NSHomeDirectory() + "/Library/Caches/AemiHTMLCorpus/pages"
        let names = ["rust-lang.html", "hackernews.html", "python-htmlparser.html", "whatwg-syntax.html"]
        for name in names {
            guard let data = FileManager.default.contents(atPath: directory + "/" + name).map(Array.init) else {
                continue
            }
            let whole = Html5libTree.dump(HTMLParser.parse(data), fragment: false)
            let streamed = Html5libTree.dump(parsed(data, pieces: chunks(data, every: size)), fragment: false)
            #expect(streamed == whole, "\(name) in pieces of \(size)")
        }
    }

    /// Markup built from the pieces that make trouble: tags, references, comments, a doctype, CDATA, script text, NUL, CR LF, multi-byte characters.
    private static let pieces: [String] = [
        "<p>", "</p>", "<div class=a id='b' hidden>", "</div>", "<a href=\"x&amp;y\">", "</a>", "<b>", "<i>", "</b>",
        "</i>", "<table>", "<tr>", "<td>", "</td>", "</table>", "<select>", "<option>",
        "<script>", "</script>", "if (a < b && c) { x = '</scr' + 'ipt>' }", "<!--", "-->", "<!-- x -->",
        "<!DOCTYPE html>", "<![CDATA[", "]]>", "<svg>", "<math>", "<mi>", "</svg>", "<title>", "</title>",
        "<textarea>", "</textarea>", "&amp;", "&notin;", "&#x1F600;", "&#0;", "&", "&am", "text ", "more text\n",
        "\r\n", "\r", "\u{0}", "é", "日本", "🙂", "<", "</", "<!", "<?php x ?>", "=", "\"", "'", ">",
        "<br/>", "<img src=x>", "<template>", "</template>", "<noscript>", "<style>", "</style>", "<plaintext>",
        "<frameset>", "<h1>", "</h1>", "<li>", "<ul>", "</ul>"
    ]

    @Test func `random markup cut at random places gives the tree and the tokens of the whole`() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 1_500 {
            var text = ""
            for _ in 0 ..< Int.random(in: 1 ... 30, using: &generator) {
                text += Self.pieces.randomElement(using: &generator) ?? ""
            }
            let data = Array(text.utf8)
            var cuts = Set<Int>()
            for _ in 0 ..< Int.random(in: 1 ... 6, using: &generator) {
                cuts.insert(Int.random(in: 1 ... Swift.max(1, data.count), using: &generator))
            }
            var pieces: [[UInt8]] = []
            var start = 0
            for cut in cuts.sorted() where cut > start && cut <= data.count {
                pieces.append(Array(data[start ..< cut]))
                start = cut
            }
            pieces.append(Array(data[start...]))
            let whole = Html5libTree.dump(HTMLParser.parse(data), fragment: false)
            let streamed = Html5libTree.dump(parsed(data, pieces: pieces), fragment: false)
            #expect(streamed == whole, "\(text.debugDescription) cut at \(cuts.sorted())")
            let wholeTokens = Html5libTokenizer.lines(HTMLTokenizer.tokenize(data, options: HTMLTokenizer.Options()))
            let streamedTokens = Html5libTokenizer.lines(HTMLTokenizer.tokenizeStreaming(data, cuts: cuts.sorted()))
            #expect(streamedTokens == wholeTokens, "\(text.debugDescription) cut at \(cuts.sorted())")
        }
    }

    @Test func `a token larger than every piece costs a linear time`() {
        // A comment of two megabytes, fed in pieces of 100 bytes: without the waiting it is re-read at every piece.
        let data = Array("<!--".utf8) + Array(repeating: 0x61, count: 2_000_000) + Array("--><p>x".utf8)
        let started = ContinuousClock.now
        let document = parsed(data, pieces: chunks(data, every: 100))
        let elapsed = ContinuousClock.now - started
        #expect(document.nodeCount > 3)
        #expect(elapsed < .seconds(20), "took \(elapsed)")
    }

    @Test func `errors are the same however the input is cut`() {
        let data = Array("<p>a\u{0}b</p><!--x\u{1}y-->".utf8) + [0xEF, 0xB7, 0x90] + Array("</p>&#0;".utf8)
        var options = HTMLParser.Options()
        options.collectsErrors = true
        let whole = HTMLParser.parse(data, options: options).errors.map(\.code).sorted { $0.rawValue < $1.rawValue }
        let streamed = parsed(data, pieces: chunks(data, every: 3), options: options).errors.map(\.code)
            .sorted { $0.rawValue < $1.rawValue }
        #expect(whole == streamed)
        #expect(!whole.isEmpty)
    }
}
