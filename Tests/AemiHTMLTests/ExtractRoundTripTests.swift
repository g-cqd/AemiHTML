import AemiMarkdown
import Testing

@testable import AemiHTML

/// The Markdown an extraction writes, read by AemiMarkdown, means what the page said: the same text, and the structure the page had.
@Suite("Extracted Markdown, read back")
struct ExtractRoundTripTests {
    private func extracted(_ html: String, _ format: HTMLExtractOptions.Format) -> String {
        var options = HTMLExtractOptions()
        options.format = format
        return HTMLExtractor.extract("<body>" + html, options: options).sections.map(\.content)
            .joined(separator: "\n\n")
    }

    /// The words of a Markdown document as AemiMarkdown reads them: the text of every leaf that is text, an entity decoded, breaks as spaces.
    private func words(_ markdown: String) -> String {
        let document = MarkdownParser.parse(Array(markdown.utf8))
        var out: [UInt8] = []
        var skip = 0
        for event in document.events {
            switch event {
                case .enter(let node):
                    if node.kind == .link || node.kind == .image { skip = 0 }
                case .exit(let node):
                    switch node.kind {
                        case .paragraph, .heading, .listItem, .tableCell, .codeBlock, .blockQuote: out.append(0x20)
                        default: break
                    }
                case .leaf(let node):
                    switch node.kind {
                        case .text, .codeLine: out.append(contentsOf: document.decode(node.range))
                        case .entity: out.append(contentsOf: document.decode(node.range))
                        case .softBreak, .hardBreak: out.append(0x20)
                        default: break
                    }
                    _ = skip
            }
        }
        return String(decoding: out, as: UTF8.self).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
    }

    private func counts(_ markdown: String) -> [NodeKind: Int] {
        var found: [NodeKind: Int] = [:]
        for event in MarkdownParser.parse(Array(markdown.utf8)).events {
            switch event {
                case .enter(let node), .leaf(let node): found[node.kind, default: 0] += 1
                case .exit: break
            }
        }
        return found
    }

    @Test(arguments: [
        "<p>2 * 3 = 6, a_b_c, *x*, **y**, [z], `w`, \\ back, <tag>, &amp; and #hash</p>",
        "<p># not a heading</p><p>1. not a list</p><p>- not a list</p><p>&gt; not a quote</p><p>+ plus</p>",
        "<p>~~not struck~~ and ~single~ and <b>real</b></p>",
        "<h1>Title with * star</h1><p>text</p>", "<ul><li>one<li>two<ul><li>three</ul></ul>",
        "<ol><li>a<li>b</ol><p>after</p>",
        "<blockquote><p>q1</p><blockquote><p>q2</p></blockquote></blockquote>",
        "<pre>code *not* emphasis\n  indented\n</pre><p>tail</p>",
        "<table><tr><th>a<th>b<tr><td>1 | 2<td>`x`</table>", "<p>a <a href=\"/p?x=1&amp;y=2\">link *text*</a> b</p>",
        "<p>line one<br>line two</p>",
        "<p>é ü 日本語 &#x1F600; text</p>"
    ])
    func `the text reads back the same`(html: String) {
        let markdown = extracted(html, .markdown)
        let plain = extracted(html, .plainText).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
        // Pipes in a table cell and the table's own bars are Markdown's; compare without them.
        func normalized(_ text: String) -> String {
            text.split(separator: " ").filter { $0 != "|" && !$0.allSatisfy { $0 == "-" } }.joined(separator: " ")
        }
        #expect(normalized(words(markdown)) == normalized(plain), "\(html.debugDescription)\n\(markdown)")
    }

    @Test func `the structure comes back`() {
        let html =
            "<h4>H</h4><p>p</p><ul><li>a<li>b<ol><li>c</ol></ul><pre><code class=language-swift>x</code></pre><blockquote><p>q</p></blockquote><hr><table><tr><th>a<tr><td>b</table>"
        let found = counts(extracted(html, .markdown))
        #expect(
            found[.heading] == 1 && found[.list] == 2 && found[.listItem] == 3 && found[.codeBlock] == 1,
            "\(found)"
        )
        #expect(found[.blockQuote] == 1 && found[.table] == 1 && found[.thematicBreak] == 1)
    }

    @Test func `a code fence names its language`() {
        let markdown = extracted("<pre><code class=\"language-rust\">fn main() {}</code></pre>", .markdown)
        let document = MarkdownParser.parse(Array(markdown.utf8))
        var info = ""
        for event in document.events {
            if case .leaf(let node) = event, node.kind == .infoString {
                info = String(decoding: document.source[node.range], as: UTF8.self)
            }
        }
        #expect(info == "rust")
    }
}
