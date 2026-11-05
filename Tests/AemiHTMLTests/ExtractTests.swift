import Testing

@testable import AemiHTML

/// The behaviour of ADHTML's extraction suite, on the new engine, and the cases it got wrong (each marked "was").
@Suite("Extraction to Markdown and plain text")
struct ExtractTests {
    private func markdown(_ html: String, _ configure: (inout HTMLExtractOptions) -> Void = { _ in }) -> String {
        var options = HTMLExtractOptions()
        configure(&options)
        return HTMLExtractor.extract("<body>" + html, options: options).sections.map(\.content)
            .joined(separator: "\n\n---SECTION---\n\n")
    }

    private func text(_ html: String) -> String { markdown(html) { $0.format = .plainText } }

    // MARK: Markdown

    @Test func `inline emphasis, headings, links and code`() {
        #expect(markdown("<p>Hello <strong>world</strong> and <em>you</em></p>") == "Hello **world** and *you*")
        #expect(markdown("<p>see <a href=\"/x\">the docs</a></p>") == "see [the docs](/x)")
        #expect(markdown("<p>call <code>foo()</code> now</p>") == "call `foo()` now")
        #expect(markdown("<h4>Title</h4><p>Body</p>") == "#### Title\n\nBody")
    }

    @Test func `a named anchor keeps its text`() {
        #expect(markdown("<p>see <a name=\"top\">top</a></p>") == "see top")
    }

    @Test func `lists, ordered and unordered, with links inside items`() {
        #expect(markdown("<ul><li>a</li><li>b</li></ul>") == "- a\n- b")
        #expect(markdown("<ol start=3><li>one</li><li>two</li></ol>") == "3. one\n4. two")
        #expect(markdown("<ul><li><a href=\"/x\">y</a> tail</li></ul>") == "- [y](/x) tail")
    }

    @Test func `a nested list stays nested (was: flattened into the item's line)`() {
        #expect(markdown("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>") == "- a\n  - b\n- c")
        #expect(markdown("<ol><li>a<ol><li>b</li></ol></li></ol>") == "1. a\n   1. b")
    }

    @Test func `a code block is fenced with its language, and a fence is longer than any backticks inside`() {
        #expect(markdown("<pre>let x = 1\nlet y = 2</pre>") == "```\nlet x = 1\nlet y = 2\n```")
        #expect(markdown("<pre><code class=\"language-swift\">let x = 1</code></pre>") == "```swift\nlet x = 1\n```")
        #expect(markdown("<pre>a ``` b</pre>") == "````\na ``` b\n````")
        #expect(markdown("<p><code>a `b` c</code></p>") == "``a `b` c``")
    }

    @Test func `a quote, a rule, an image`() {
        #expect(markdown("<blockquote><p>quoted</p></blockquote>") == "> quoted")
        #expect(markdown("<blockquote><p>a</p><p>b</p></blockquote>") == "> a\n>\n> b")
        #expect(markdown("<p>a</p><hr><p>b</p>") == "a\n\n---\n\nb")
        #expect(markdown("<p><img src=\"/i.png\" alt=\"pic\"></p>") == "![pic](/i.png)")
        #expect(markdown("<p><img src=\"/i.png\" alt=\"pic\"></p>") { $0.images = .altText } == "pic")
        #expect(markdown("<p><img src=\"/i.png\" alt=\"pic\"></p>") { $0.images = .drop } == "")
    }

    @Test func `a table is a table (was: its cells ran together as paragraphs)`() {
        let table = markdown("<table><tr><th>a</th><th>b</th></tr><tr><td>1</td><td>x | y</td></tr></table>")
        #expect(table == "| a | b |\n| --- | --- |\n| 1 | x \\| y |")
    }

    @Test func `emphasis never has a space inside its delimiters`() {
        #expect(markdown("<p>foo<b> bar </b>baz</p>") == "foo **bar** baz")
        #expect(markdown("<p><em> </em>x</p>") == "x")
    }

    @Test func `text that looks like Markdown is escaped`() {
        #expect(
            markdown("<p>2 * 3 = 6 and a_b and *x* and [y] and `z`</p>")
                == "2 \\* 3 = 6 and a_b and \\*x\\* and \\[y\\] and \\`z\\`"
        )
        #expect(markdown("<p># not a heading</p>") == "\\# not a heading")
        #expect(markdown("<p>1. not a list</p>") == "1\\. not a list")
        #expect(markdown("<p>- not a list</p>") == "\\- not a list")
        #expect(markdown("<p>&lt;b&gt; and &amp;amp;</p>") == "\\<b> and \\&amp;")
    }

    @Test func `a task list keeps its boxes`() {
        #expect(
            markdown("<ul><li><input type=checkbox checked> done</li><li><input type=checkbox> todo</li></ul>")
                == "- [x] done\n- [ ] todo"
        )
    }

    @Test func `a link destination with a space or a parenthesis is written safely`() {
        #expect(markdown("<a href=\"/a b\">t</a>") == "[t](</a b>)")
        #expect(markdown("<a href=\"/a(b)\">t</a>") == "[t](/a(b))")
    }

    // MARK: Dropping

    @Test func `scripts, styles and chrome are dropped, and so is hidden text`() {
        #expect(markdown("<p>keep</p><script>var x=1</script><style>p{}</style><p>this</p>") == "keep\n\nthis")
        #expect(text("<nav>menu</nav><p>body text</p>") == "body text")
        #expect(
            markdown(
                "<p>a</p><p hidden>secret</p><div aria-hidden=\"true\">secret</div><p style=\"display: none\">secret</p><p>b</p>"
            ) == "a\n\nb"
        )
        #expect(markdown("<p>a</p><p hidden>shown</p>") { $0.dropsHiddenContent = false } == "a\n\nshown")
    }

    @Test func `a page header goes, an article's header stays (was: every header went)`() {
        #expect(
            markdown("<header>site</header><article><header><h1>Title</h1></header><p>x</p></article>")
                == "# Title\n\nx"
        )
    }

    @Test func `links keep only safe destinations and a resolver may rewrite or drop`() {
        #expect(markdown("<a href=\"javascript:alert(1)\">t</a>") == "t")
        #expect(markdown("<a href=\"mailto:a@b.c\">t</a>") == "[t](mailto:a@b.c)")
        #expect(markdown("<a href=\"old\">t</a>") { $0.linkResolver = { _ in "new" } } == "[t](new)")
        #expect(markdown("<a href=\"x\">t</a>") { $0.linkResolver = { _ in nil } } == "t")
    }

    // MARK: Plain text

    @Test func `plain text separates blocks and collapses inline whitespace`() {
        #expect(text("<div><p>first para</p><p>second para</p></div>") == "first para\n\nsecond para")
        #expect(text("<p>  lots   of\n   space  </p>") == "lots of space")
        #expect(text("<p>a <b>b</b> <a href=\"/x\">c</a></p>") == "a b c")
    }

    // MARK: Pages

    private let page = """
        <html><head><title>Page Title</title><meta name="description" content="A short desc">
        <meta property="og:title" content="OG Title"></head>
        <body><nav>menu</nav><main><h1>Heading One</h1><p>Intro paragraph.</p>
        <h2>Section A</h2><p>Content A.</p><h2>Section B</h2><p>Content B.</p></main>
        <footer>foot</footer></body></html>
        """

    @Test func `the title, the description and the sections`() {
        var options = HTMLExtractOptions()
        options.format = .plainText
        let page = HTMLExtractor.extract(page, options: options)
        #expect(page.title == "OG Title" && page.description == "A short desc")
        #expect(page.sections.count == 3)
        #expect(page.sections[0] == HTMLSection(heading: nil, content: "Heading One\n\nIntro paragraph."))
        #expect(page.sections[1] == HTMLSection(heading: "Section A", content: "Content A."))
        #expect(page.sections[2] == HTMLSection(heading: "Section B", content: "Content B."))
    }

    @Test func `one section without headings, a title from the h1, h3 when there is no h2`() {
        let flat = HTMLExtractor.extract(
            "<html><head><title>T</title></head><body><article><p>only para</p></article></body></html>"
        )
        #expect(
            flat.title == "T" && flat.description == nil && flat.sections.count == 1
                && flat.sections[0].content == "only para"
        )
        #expect(HTMLExtractor.extract("<body><main><h1>The Heading</h1><p>x</p></main></body>").title == "The Heading")
        let h3 = HTMLExtractor.extract("<main><h3>A</h3><p>x</p><h3>B</h3><p>y</p></main>")
        #expect(h3.sections == [HTMLSection(heading: "A", content: "x"), HTMLSection(heading: "B", content: "y")])
    }

    @Test func `headings inside wrappers split too (was: only top-level children did)`() {
        let found = HTMLExtractor.extract(
            "<main><div><h2>A</h2><p>x</p></div><section><h2>B</h2><p>y</p></section></main>"
        )
        #expect(found.sections == [HTMLSection(heading: "A", content: "x"), HTMLSection(heading: "B", content: "y")])
    }

    @Test func `the container by selector, and the Markdown of a section`() {
        let chosen = HTMLExtractor.extract("<body><div>noise</div><div class=\"content\"><p>real</p></div></body>") {
            _ in
        }
        #expect(chosen.sections[0].content == "real")
        var options = HTMLExtractOptions()
        options.containerSelector = "#b"
        let byID = HTMLExtractor.extract(
            "<body><div id=a><p>no</p></div><div id=b><p>yes</p></div></body>",
            options: options
        )
        #expect(byID.sections[0].content == "yes")
        let linked = HTMLExtractor.extract(
            "<main><h2>S</h2><p>see <a href=\"/x\">link</a></p><ul><li>a</li></ul></main>"
        )
        #expect(linked.sections[0].content == "see [link](/x)\n\n- a")
    }

    @Test func `deep nesting and long documents do not overflow the stack`() {
        let deep = String(repeating: "<div>", count: 20_000) + "x" + String(repeating: "</div>", count: 20_000)
        #expect(markdown(deep) == "x")
        let list = String(repeating: "<ul><li>", count: 2_000) + "leaf"
        #expect(markdown(list).hasSuffix("leaf"))
    }
}

extension HTMLExtractor {
    fileprivate static func extract(_ html: String, configure: (inout HTMLExtractOptions) -> Void) -> HTMLExtractedPage
    {
        var options = HTMLExtractOptions()
        configure(&options)
        return extract(html, options: options)
    }
}
