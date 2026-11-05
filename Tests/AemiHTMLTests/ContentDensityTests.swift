import Testing

@testable import AemiHTML

@Suite("The container found by text and link density")
struct ContentDensityTests {
    private static let sentence = "The quick brown fox jumps over the lazy dog while the band plays on and on. "

    private static func paragraphs(_ count: Int) -> String {
        String(repeating: "<p>\(sentence)\(sentence)</p>", count: count)
    }

    private static func links(_ count: Int) -> String {
        (0 ..< count).map { "<li><a href=\"/page/\($0)\">Related article number \($0) with a long title</a></li>" }
            .joined()
    }

    private func id(of node: HTMLDocument.Node?, in document: HTMLDocument) -> String {
        guard let node else { return "none" }
        let name = String(decoding: document.name(node), as: UTF8.self)
        return name + (document.attribute("id", of: node).map { "#" + String(decoding: $0, as: UTF8.self) } ?? "")
    }

    private func found(_ html: String) -> String {
        let document = HTMLParser.parse(Array(html.utf8))
        return id(of: HTMLExtractor.densestContainer(in: document), in: document)
    }

    @Test func `the article is found in a page with a link-heavy sidebar and no marker`() {
        let html = """
            <body><div id=wrap><div id=side><ul>\(Self.links(40))</ul></div>
            <div id=story><h1>Title</h1>\(Self.paragraphs(8))</div></div></body>
            """
        #expect(found(html) == "div#story")
    }

    @Test func `the text beside the links is what counts, not the links`() {
        let html = "<body><div id=nav>\(Self.links(60))</div><div id=text>\(Self.paragraphs(2))</div></body>"
        #expect(found(html) == "div#text")
    }

    @Test func `a wrapper that adds nothing is not preferred to what it wraps`() {
        let html = "<body><div id=outer><div id=inner>\(Self.paragraphs(6))</div></div></body>"
        #expect(found(html) == "div#inner")
    }

    @Test func `a page that is all text gives its smallest element that holds it`() {
        #expect(found("<body>\(Self.paragraphs(6))</body>") == "body")
    }

    @Test func `a page of parallel blocks has no one container, so there is no answer`() {
        // A navigation bar of links, then six blocks of the same size: the link-heavy body scores low, one block scores best, and one block is a sixth of the text.
        let blocks = (0 ..< 6).map { "<section id=s\($0)>\(Self.paragraphs(2))</section>" }.joined()
        let html = "<body><ul>\(Self.links(300))</ul>\(blocks)</body>"
        #expect(found(html) == "none")
        let document = HTMLParser.parse(Array(html.utf8))
        // With the share asked for lowered, the densest block is taken.
        #expect(HTMLExtractor.densestContainer(in: document, minimumShare: 0.1) != nil)
        // One block that is most of the page is a container.
        let dominant =
            "<body><ul>\(Self.links(300))</ul><div id=big>\(Self.paragraphs(30))</div><div>\(Self.paragraphs(1))</div></body>"
        #expect(found(dominant) == "div#big")
    }

    @Test func `a page that is all links has no article, and a short one has no text to find`() {
        // All links: the score is zero everywhere.
        #expect(found("<body><div id=a>\(Self.links(50))</div></body>") == "none")
        #expect(found("<body><div id=a>short</div></body>") == "none")
        #expect(found("") == "none")
    }

    @Test func `what the extraction drops is counted in neither the text nor the links`() {
        // A navigation element with a lot of plain text, a hidden block, and a script: none of it is the page's.
        let html = """
            <body><nav>\(Self.paragraphs(10))</nav><div hidden>\(Self.paragraphs(10))</div>
            <script>\(Self.sentence)\(Self.sentence)\(Self.sentence)\(Self.sentence)</script>
            <div id=real>\(Self.paragraphs(2))</div></body>
            """
        #expect(found(html) == "div#real")
        let document = HTMLParser.parse(Array(html.utf8))
        // With hidden content kept, the hidden block is text like any other.
        let kept = HTMLExtractor.densestContainer(in: document, dropsHiddenContent: false)
        #expect(id(of: kept, in: document) != "div#real")
    }

    @Test func `the option off leaves the body, on takes the densest element`() {
        let html = """
            <body><div id=side>\(Self.links(40))</div><div id=story>\(Self.paragraphs(6))</div></body>
            """
        var options = HTMLExtractOptions()
        let plain = HTMLExtractor.extract(html, options: options)
        options.fallsBackToTextDensity = true
        let dense = HTMLExtractor.extract(html, options: options)
        let plainText = plain.sections.map(\.content).joined()
        let denseText = dense.sections.map(\.content).joined()
        #expect(plainText.contains("Related article"))
        #expect(!denseText.contains("Related article"))
        #expect(denseText.contains("quick brown fox"))
    }

    @Test func `a named container, or a selector, is not overridden`() {
        let html = """
            <body><div id=side>\(Self.links(40))</div><main id=m>\(Self.paragraphs(6))</main><div id=big>\(Self.paragraphs(9))</div></body>
            """
        var options = HTMLExtractOptions()
        options.fallsBackToTextDensity = true
        let named = HTMLExtractor.extract(html, options: options)
        #expect(named.sections.map(\.content).joined().contains("quick brown fox"))
        // `main` holds a real share of the text (a `main` with a sliver of it would be passed over, as before), so it is the container: the longer `div` beside it is not.
        #expect(named.sections.map(\.content).joined().count < 1_200)
        options.containerSelector = "#big"
        let selected = HTMLExtractor.extract(html, options: options)
        #expect(selected.sections.map(\.content).joined().count > 1_200)
    }

    @Test func `a large page is scored in time linear in its size`() {
        let small =
            "<body>"
            + String(repeating: "<div>" + Self.paragraphs(1) + "<ul>" + Self.links(2) + "</ul></div>", count: 200)
            + "</body>"
        let large =
            "<body>"
            + String(repeating: "<div>" + Self.paragraphs(1) + "<ul>" + Self.links(2) + "</ul></div>", count: 2_000)
            + "</body>"
        let clock = ContinuousClock()
        let smallDocument = HTMLParser.parse(Array(small.utf8))
        let largeDocument = HTMLParser.parse(Array(large.utf8))
        let first = clock.measure { _ = HTMLExtractor.densestContainer(in: smallDocument) }
        let second = clock.measure { _ = HTMLExtractor.densestContainer(in: largeDocument) }
        // Ten times the page, so about ten times the time; a quadratic cost would be a hundred. Generous, since a short run is noisy.
        #expect(second < first * 40 + .milliseconds(5), "\(first) for 200, \(second) for 2,000")
    }
}
