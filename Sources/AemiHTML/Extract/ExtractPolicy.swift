extension HTMLDocument {
    /// Elements that start and end a block of text.
    func isBlock(_ node: Node) -> Bool {
        guard kind(node) == .element, namespace(node) == .html else { return false }
        switch HTMLName(rawValue: atom(node)) ?? .unknown {
            case .address, .article, .aside, .blockquote, .body, .center, .details, .dialog, .dir, .div, .dl, .dd, .dt,
                .fieldset, .figcaption, .figure, .footer,
                .form, .h1, .h2, .h3, .h4, .h5, .h6, .header, .hgroup, .hr, .html, .li, .main, .menu, .nav, .ol, .p,
                .pre, .search, .section, .summary, .table,
                .tbody, .thead, .tfoot, .tr, .ul, .listing:
                return true
            default: return false
        }
    }

    func hasAncestor(_ node: Node, in names: NameSet) -> Bool {
        var parent = self.parent(node)
        while !parent.isNone, parent != root {
            if kind(parent) == .element, namespace(parent) == .html, names.contains(atom(parent)) { return true }
            parent = self.parent(parent)
        }
        return false
    }

    private func attributeIs(_ node: Node, _ name: String, _ value: String) -> Bool {
        guard let found = attribute(name, of: node) else { return false }
        return found.count == value.utf8.count && zip(found, value.utf8).allSatisfy { HTMLBuilderRules.lower($0) == $1 }
    }

    /// Class names that mark chrome, matched as whole words: MediaWiki's edit links and navigation boxes, sidebars, breadcrumbs, cookie banners and advertisements.
    private static let chromeClasses: Set<String> = [
        "mw-editsection", "navbox", "catlinks", "printfooter", "noprint", "sidebar", "breadcrumb", "breadcrumbs",
        "cookie-banner", "cookie-consent",
        "cookies", "advert", "advertisement", "newsletter", "share-buttons", "social-share"
    ]

    private func hasChromeClass(_ node: Node) -> Bool {
        guard let value = attribute("class", of: node) else { return false }
        var word: [UInt8] = []
        func check() -> Bool { !word.isEmpty && Self.chromeClasses.contains(String(decoding: word, as: UTF8.self)) }
        for byte in value {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A {
                if check() { return true }
                word.removeAll(keepingCapacity: true)
            } else {
                word.append(HTMLBuilderRules.lower(byte))
            }
        }
        return check()
    }

    /// Whether the element is left out of an extraction with all that is in it: scripts and styles, navigation and other chrome, and what a reader cannot see.
    func isDropped(_ node: Node, hidden: Bool) -> Bool {
        guard kind(node) == .element else { return false }
        let space = namespace(node)
        let name = HTMLName(rawValue: atom(node)) ?? .unknown
        if space == .svg { return name == .svg }
        if space != .html { return false }
        switch name {
            case .script, .style, .noscript, .template, .nav, .aside, .canvas, .iframe, .object, .embed, .select,
                .datalist, .head, .noframes, .noembed,
                .frameset, .frame, .title:
                return true
            case .footer, .header:
                if !hasAncestor(node, in: NameSet.contentContainers) { return true }
            case .input:
                if attributeIs(node, "type", "hidden") { return true }
            default: break
        }
        if let role = attribute("role", of: node) {
            let lowered = String(decoding: role.map(HTMLBuilderRules.lower), as: UTF8.self)
            switch lowered {
                case "navigation", "complementary", "search": return true
                case "banner", "contentinfo": if !hasAncestor(node, in: NameSet.contentContainers) { return true }
                default: break
            }
        }
        if hasChromeClass(node) { return true }
        guard hidden else { return false }
        if attribute("hidden", of: node) != nil || attributeIs(node, "aria-hidden", "true") { return true }
        if let style = attribute("style", of: node) {
            let squeezed = style.filter { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }.map(HTMLBuilderRules.lower)
            let text = String(decoding: squeezed, as: UTF8.self)
            if text.contains("display:none") || text.contains("visibility:hidden") { return true }
        }
        return false
    }

    /// Whether the destination of a link may be kept: http, https, mailto and tel, a fragment, or a reference with no scheme.
    static func isSafeDestination(_ destination: String) -> Bool {
        let trimmed = destination.drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let colon = trimmed.firstIndex(of: ":") else { return true }
        let scheme = trimmed[..<colon].lowercased()
        if scheme.contains("/") || scheme.contains("?") || scheme.contains("#") { return true }
        return scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel"
    }
}

extension NameSet {
    /// An element whose `header` or `footer` is part of the content rather than of the page.
    static let contentContainers = NameSet(.article, .section, .blockquote, .li, .td, .th, .details, .figure, .dialog)
}
