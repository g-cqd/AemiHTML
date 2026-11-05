/// Extraction of a page's content (ADHTML's `HTMLDocument.extract`, rebuilt on `HTMLDocument`): the title, the description, and the content cut into sections, as Markdown or plain text.
///
/// ```swift
/// let page = HTMLExtractor.extract(Array(html.utf8))
/// print(page.title ?? "", page.sections.map(\.content))
/// ```
public enum HTMLExtractor {
    public static func extract(_ html: [UInt8], options: HTMLExtractOptions = HTMLExtractOptions()) -> HTMLExtractedPage
    {
        var parserOptions = HTMLParser.Options()
        parserOptions.scripting = options.scripting
        return extract(HTMLParser.parse(html, options: parserOptions), options: options)
    }

    /// The page in the bytes of a file or a response, in whatever encoding: the encoding is sniffed as `HTMLParser.parse(encoded:)` does, with the transport layer's `charset` if there is one.
    public static func extract(
        encoded bytes: [UInt8],
        transportEncoding: String? = nil,
        options: HTMLExtractOptions = HTMLExtractOptions()
    ) -> HTMLExtractedPage {
        var parserOptions = HTMLParser.Options()
        parserOptions.scripting = options.scripting
        return extract(
            HTMLParser.parse(encoded: bytes, transportEncoding: transportEncoding, options: parserOptions),
            options: options
        )
    }

    public static func extract(_ html: String, options: HTMLExtractOptions = HTMLExtractOptions()) -> HTMLExtractedPage
    {
        extract(Array(html.utf8), options: options)
    }

    public static func extract(_ document: HTMLDocument, options: HTMLExtractOptions = HTMLExtractOptions())
        -> HTMLExtractedPage
    {
        let facts = scan(document, options: options)
        let container = facts.container ?? facts.body ?? document.root
        return HTMLExtractedPage(
            title: facts.title(document),
            description: facts.description(document),
            sections: sections(document, container, options)
        )
    }

    /// The content of a subtree as Markdown or plain text, in one piece.
    public static func render(
        _ document: HTMLDocument,
        _ node: HTMLDocument.Node,
        options: HTMLExtractOptions = HTMLExtractOptions()
    ) -> String {
        var writer = MarkdownWriter(document: document, options: options)
        var walker = document.walk(node)
        while let event = walker.next() { writer.handle(event, &walker) }
        return writer.take()
    }

    // MARK: Finding things

    struct Facts {
        var ogTitle: HTMLDocument.Node = .none
        var titleElement: HTMLDocument.Node = .none
        var firstHeading: HTMLDocument.Node = .none
        var description: HTMLDocument.Node = .none
        var ogDescription: HTMLDocument.Node = .none
        var body: HTMLDocument.Node?
        var container: HTMLDocument.Node?
        /// The fallbacks in order of preference, the first match of each.
        var fallbacks: [HTMLDocument.Node] = [.none, .none, .none, .none, .none, .none]

        func text(_ document: HTMLDocument, _ node: HTMLDocument.Node, attribute: String? = nil) -> String? {
            guard !node.isNone else { return nil }
            let value: String
            if let attribute {
                value = document.attribute(attribute, of: node).map { String(decoding: $0, as: UTF8.self) } ?? ""
            } else {
                var options = HTMLExtractOptions()
                options.format = .plainText
                options.dropsHiddenContent = false
                value = HTMLExtractor.render(document, node, options: options).collapsingWhitespace()
            }
            let trimmed = value.collapsingWhitespace()
            return trimmed.isEmpty ? nil : trimmed
        }

        func title(_ document: HTMLDocument) -> String? {
            text(document, ogTitle, attribute: "content") ?? text(document, titleElement)
                ?? text(document, firstHeading)
        }

        func description(_ document: HTMLDocument) -> String? {
            text(document, description, attribute: "content") ?? text(document, ogDescription, attribute: "content")
        }
    }

    /// One pass over the document: the facts the extraction needs, and the container by the selector or the fallbacks.
    static func scan(_ document: HTMLDocument, options: HTMLExtractOptions) -> Facts {
        var facts = Facts()
        let selector = options.containerSelector.map(Selector.init)
        for node in document.descendants(of: document.root) where document.kind(node) == .element {
            guard document.namespace(node) == .html else { continue }
            let name = HTMLName(rawValue: document.atom(node)) ?? .unknown
            switch name {
                case .title where facts.titleElement.isNone: facts.titleElement = node
                case .h1 where facts.firstHeading.isNone: facts.firstHeading = node
                case .body where facts.body == nil: facts.body = node
                case .meta:
                    let value = document.attribute("content", of: node).map { !$0.isEmpty } ?? false
                    if value, let key = document.attribute("name", of: node), equals(key, "description"),
                        facts.description.isNone
                    {
                        facts.description = node
                    }
                    if value, let key = document.attribute("property", of: node) {
                        if equals(key, "og:title"), facts.ogTitle.isNone { facts.ogTitle = node }
                        if equals(key, "og:description"), facts.ogDescription.isNone { facts.ogDescription = node }
                    }
                default: break
            }
            if let selector, facts.container == nil, selector.matches(node, document) { facts.container = node }
            if selector == nil {
                if name == .main, facts.fallbacks[0].isNone { facts.fallbacks[0] = node }
                if name == .article, facts.fallbacks[1].isNone { facts.fallbacks[1] = node }
                if let role = document.attribute("role", of: node), equals(role, "main"), facts.fallbacks[2].isNone {
                    facts.fallbacks[2] = node
                }
                if Selector.class("content").matches(node, document), facts.fallbacks[3].isNone {
                    facts.fallbacks[3] = node
                }
                if Selector.id("content").matches(node, document), facts.fallbacks[4].isNone {
                    facts.fallbacks[4] = node
                }
                if Selector.id("contents").matches(node, document), facts.fallbacks[5].isNone {
                    facts.fallbacks[5] = node
                }
            }
        }
        if selector == nil {
            // A fallback container must hold a real share of the page's text: a stray `.content` element must not stand for the page.
            let whole = facts.body.map { textLength(document, $0) } ?? 0
            facts.container = facts.fallbacks.first { !$0.isNone && textLength(document, $0) * 5 >= whole }
        }
        return facts
    }

    /// The bytes of text under `node`.
    static func textLength(_ document: HTMLDocument, _ node: HTMLDocument.Node) -> Int {
        var total = 0
        for child in document.descendants(of: node) where document.kind(child) == .text {
            total += document.data(child).count
        }
        return total
    }

    static func equals(_ bytes: ArraySlice<UInt8>, _ word: String) -> Bool {
        HTMLBuilderRules.equalsIgnoringCase(bytes, word)
    }

    /// A simple selector: `tag`, `.class` or `#id`.
    enum Selector {
        case tag(String)
        case `class`(String)
        case id(String)

        init(_ text: String) {
            if text.hasPrefix(".") {
                self = .class(String(text.dropFirst()))
            } else if text.hasPrefix("#") {
                self = .id(String(text.dropFirst()))
            } else {
                self = .tag(text.lowercased())
            }
        }

        func matches(_ node: HTMLDocument.Node, _ document: HTMLDocument) -> Bool {
            switch self {
                case .tag(let name): return document.name(node).elementsEqual(name.utf8)
                case .id(let id): return document.attribute("id", of: node).map { $0.elementsEqual(id.utf8) } ?? false
                case .class(let name):
                    guard let value = document.attribute("class", of: node) else { return false }
                    return String(decoding: value, as: UTF8.self)
                        .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).contains { $0 == name }
            }
        }
    }

    // MARK: Sections

    /// The content of `container` cut at `h2` (or `h3`, if there is no `h2` in it): a section is a heading and what follows it, up to the next. Text before the first heading is a section with no heading.
    static func sections(_ document: HTMLDocument, _ container: HTMLDocument.Node, _ options: HTMLExtractOptions)
        -> [HTMLSection]
    {
        var splitName = HTMLName.none
        if options.splitsSections {
            var hasH2 = false
            var hasH3 = false
            for node in document.descendants(of: container)
            where document.kind(node) == .element && document.namespace(node) == .html {
                let name = HTMLName(rawValue: document.atom(node))
                if name == .h2 { hasH2 = true }
                if name == .h3 { hasH3 = true }
            }
            splitName = hasH2 ? .h2 : (hasH3 ? .h3 : .none)
        }
        var writer = MarkdownWriter(document: document, options: options)
        var sections: [HTMLSection] = []
        var heading: String?
        var walker = document.walk(container)
        while let event = walker.next() {
            if case .enter(let node) = event, writer.skipped.isNone, splitName != .none,
                document.kind(node) == .element, document.namespace(node) == .html,
                HTMLName(rawValue: document.atom(node)) == splitName,
                !document.isDropped(node, hidden: options.dropsHiddenContent)
            {
                let content = writer.take()
                if heading != nil || !content.isEmpty {
                    sections.append(HTMLSection(heading: heading, content: content))
                }
                var plain = options
                plain.format = .plainText
                let text = render(document, node, options: plain).collapsingWhitespace()
                heading = text.isEmpty ? nil : text
                walker.skipChildren()
                writer.skipped = node
                continue
            }
            writer.handle(event, &walker)
        }
        let content = writer.take()
        if heading != nil || !content.isEmpty || sections.isEmpty {
            sections.append(HTMLSection(heading: heading, content: content))
        }
        return sections
    }
}
