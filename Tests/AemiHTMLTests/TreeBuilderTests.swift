import Testing

@testable import AemiHTML

@Suite("The tree builder")
struct TreeBuilderTests {
    private func parse(_ html: String, _ configure: (inout HTMLParser.Options) -> Void = { _ in }) -> HTMLDocument {
        var options = HTMLParser.Options()
        configure(&options)
        return HTMLParser.parse(Array(html.utf8), options: options)
    }

    private func dump(_ html: String) -> String { Html5libTree.dump(parse(html), fragment: false) }

    @Test func `missing html, head and body are made, and a table gets its tbody`() {
        #expect(dump("x") == "| <html>\n|   <head>\n|   <body>\n|     \"x\"")
        #expect(dump("<table><td>c").contains("<tbody>\n|         <tr>\n|           <td>"))
    }

    @Test func `misnested formatting is repaired by the adoption agency`() {
        #expect(
            dump("<b>1<p>2</b>3</p>")
                == "| <html>\n|   <head>\n|   <body>\n|     <b>\n|       \"1\"\n|     <p>\n|       <b>\n|         \"2\"\n|       \"3\""
        )
    }

    @Test func `text in a table is foster parented before it`() {
        #expect(dump("<table>x<tr><td>y").hasPrefix("| <html>\n|   <head>\n|   <body>\n|     \"x\"\n|     <table>"))
    }

    @Test func `svg and mathml are foreign, with their names and attributes adjusted`() {
        let tree = dump("<svg viewbox=0><foreignobject><p>x</p></foreignobject></svg>")
        #expect(tree.contains("<svg svg>\n|       viewBox=\"0\"\n|       <svg foreignObject>\n|         <p>"))
    }

    @Test func `a template holds its content apart`() {
        #expect(dump("<template><p>a</template>").contains("<template>\n|       content\n|         <p>"))
    }

    @Test func `scripting decides whether noscript is text or markup`() {
        #expect(
            Html5libTree.dump(parse("<noscript><b>x</b></noscript>") { $0.scripting = false }, fragment: false)
                .contains("<b>")
        )
        #expect(
            Html5libTree.dump(parse("<noscript><b>x</b></noscript>") { $0.scripting = true }, fragment: false)
                .contains("\"<b>x</b>\"")
        )
    }

    @Test func `walking the arena visits the nodes in document order without recursion`() {
        let document = parse("<div><p>a<b>b</b></p><i>c</i></div>")
        var names: [String] = []
        for node in document.descendants(of: document.root) where document.kind(node) == .element {
            names.append(String(decoding: document.name(node), as: UTF8.self))
        }
        #expect(names == ["html", "head", "body", "div", "p", "b", "i"])
    }

    @Test func `hostile documents take linear time and a bounded tree`() {
        let patterns = [
            "<div>", "<b>", "<b a=1>", "<table>", "<a><table><a>", "<p>", "<td>", "<svg>", "<b><i><p></b>",
            "<select><option>", "<template>", "<li>",
            "<font color=red><p>x", "<div><b x=1></div>"
        ]
        for pattern in patterns {
            let html = Array(String(repeating: pattern, count: 20_000).utf8)
            let start = ContinuousClock.now
            let document = HTMLParser.parse(html)
            let seconds = ContinuousClock.now - start
            #expect(seconds < .seconds(30), "\(pattern): \(seconds)")
            #expect(document.nodeCount > 1)
        }
    }

    @Test func `any bytes give a document`() {
        var generator = SystemRandomNumberGenerator()
        let alphabet: [UInt8] = Array("<>/&!-?=\"' abdipt\u{0}\n[]".utf8)
        for _ in 0 ..< 400 {
            let bytes = (0 ..< Int.random(in: 0 ... 300, using: &generator))
                .map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] }
            var options = HTMLParser.Options()
            options.collectsErrors = true
            options.scripting = Bool.random()
            _ = HTMLParser.parse(bytes, options: options)
            _ = HTMLParser.parseFragment(
                bytes,
                context: ["div", "table", "select", "template", "title", "script"].randomElement() ?? "div",
                options: options
            )
        }
    }
}
