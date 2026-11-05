internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: Names

    func isElement(_ node: Node, _ name: HTMLName, in space: HTMLDocument.Namespace = .html) -> Bool {
        document.atom(node) == name.rawValue && document.namespaceRaw(node) == space.rawValue
            && document.kindRaw(node) == HTMLDocument.Kind.element.rawValue
    }

    /// Whether `node` is an HTML element with one of up to five names. Fixed arity, so nothing is allocated to ask.
    @inline(__always)
    func isHTML(
        _ node: Node,
        _ a: HTMLName,
        _ b: HTMLName = .none,
        _ c: HTMLName = .none,
        _ d: HTMLName = .none,
        _ e: HTMLName = .none
    ) -> Bool {
        guard document.namespaceRaw(node) == HTMLDocument.Namespace.html.rawValue,
            document.kindRaw(node) == HTMLDocument.Kind.element.rawValue
        else { return false }
        let atom = document.atom(node)
        return atom == a.rawValue || atom == b.rawValue || atom == c.rawValue || atom == d.rawValue
            || atom == e.rawValue
    }

    @inline(__always)
    func isHTML(_ node: Node, in set: NameSet) -> Bool {
        isHTMLElement(node) && set.contains(document.atom(node))
    }

    func name(of node: Node) -> HTMLName { HTMLName(rawValue: document.atom(node)) ?? .unknown }
    func space(of node: Node) -> HTMLDocument.Namespace { document.namespace(node) }
    func isHTMLElement(_ node: Node) -> Bool { space(of: node) == .html && document.kind(node) == .element }

    static func isHeading(_ name: HTMLName) -> Bool {
        switch name {
            case .h1, .h2, .h3, .h4, .h5, .h6: true
            default: false
        }
    }

    /// The special category of 13.2.4.2.
    func isSpecial(_ node: Node) -> Bool {
        let name = name(of: node)
        switch space(of: node) {
            case .html:
                switch name {
                    case .address, .applet, .area, .article, .aside, .base, .basefont, .bgsound, .blockquote, .body,
                        .br, .button, .caption, .center, .col,
                        .colgroup, .dd, .details, .dir, .div, .dl, .dt, .embed, .fieldset, .figcaption, .figure,
                        .footer, .form, .frame, .frameset, .h1, .h2,
                        .h3, .h4, .h5, .h6, .head, .header, .hgroup, .hr, .html, .iframe, .img, .input, .keygen, .li,
                        .link, .listing, .main, .marquee, .menu,
                        .meta, .nav, .noembed, .noframes, .noscript, .object, .ol, .p, .param, .plaintext, .pre,
                        .script, .search, .section, .select, .source,
                        .style, .summary, .table, .tbody, .td, .template, .textarea, .tfoot, .th, .thead, .title, .tr,
                        .track, .ul, .wbr, .xmp:
                        return true
                    default: return false
                }
            case .mathml:
                switch name {
                    case .mi, .mo, .mn, .ms, .mtext, .annotationXml: return true
                    default: return false
                }
            case .svg:
                switch name {
                    case .foreignObject, .desc, .title: return true
                    default: return false
                }
        }
    }

    static func isFormatting(_ name: HTMLName) -> Bool {
        switch name {
            case .a, .b, .big, .code, .em, .font, .i, .nobr, .s, .small, .strike, .strong, .tt, .u: true
            default: false
        }
    }

    // MARK: The stack of open elements

    var currentNode: Node { stack.last ?? .none }

    /// The adjusted current node (13.2.4.2): the context element in the fragment case when only the root is open.
    var adjustedCurrentNode: Node {
        if !contextElement.isNone, stack.count == 1 { return contextElement }
        return currentNode
    }

    mutating func push(_ node: Node) { stack.append(node) }

    @discardableResult
    mutating func pop() -> Node { stack.removeLast() }

    /// Pops until an HTML element with this name (or one of the names in the set) has been popped.
    mutating func popUntilHTML(_ name: HTMLName) {
        while let node = stack.popLast() {
            if isHTML(node, name) { return }
        }
    }

    mutating func popUntilHTML(in set: NameSet) {
        while let node = stack.popLast() {
            if isHTML(node, in: set) { return }
        }
    }

    mutating func popUntilHeading() {
        while let node = stack.popLast() {
            if isHTMLElement(node), Self.isHeading(name(of: node)) { return }
        }
    }

    func stackIndex(of node: Node) -> Int? { stack.lastIndex(of: node) }

    mutating func removeFromStack(_ node: Node) {
        if let index = stack.lastIndex(of: node) { stack.remove(at: index) }
    }

    // MARK: Scopes

    enum Scope { case regular, listItem, button, table }

    /// Whether `node` stops the scope search (13.2.4.2).
    func stops(_ node: Node, _ scope: Scope) -> Bool {
        let name = name(of: node)
        switch space(of: node) {
            case .html:
                switch scope {
                    case .table: return name == .html || name == .table || name == .template
                    default:
                        switch name {
                            case .applet, .caption, .html, .table, .td, .th, .marquee, .object, .select, .template:
                                return true
                            case .ol, .ul: return scope == .listItem
                            case .button: return scope == .button
                            default: return false
                        }
                }
            case .mathml:
                guard scope != .table else { return false }
                switch name {
                    case .mi, .mo, .mn, .ms, .mtext, .annotationXml: return true
                    default: return false
                }
            case .svg:
                guard scope != .table else { return false }
                switch name {
                    case .foreignObject, .desc, .title: return true
                    default: return false
                }
        }
    }

    /// Whether an HTML element for which `matches` holds is in the scope, searching from the current node up.
    func hasInScope(_ scope: Scope, where matches: (HTMLName) -> Bool) -> Bool {
        var index = stack.count - 1
        while index >= 0 {
            let node = stack[index]
            if isHTMLElement(node), matches(name(of: node)) { return true }
            if stops(node, scope) { return false }
            index -= 1
        }
        return false
    }

    func hasInScope(_ target: HTMLName, _ scope: Scope = .regular) -> Bool { hasInScope(scope) { $0 == target } }

    func hasInScope(_ node: Node, _ scope: Scope = .regular) -> Bool {
        var index = stack.count - 1
        while index >= 0 {
            if stack[index] == node { return true }
            if stops(stack[index], scope) { return false }
            index -= 1
        }
        return false
    }

    // MARK: Implied end tags

    /// 13.2.6.3: pops `dd`, `dt`, `li`, `optgroup`, `option`, `p`, `rb`, `rp`, `rt` and `rtc`, except `exclude`.
    mutating func generateImpliedEndTags(except exclude: HTMLName = .unknown) {
        while let node = stack.last, isHTMLElement(node) {
            let current = name(of: node)
            guard current != exclude else { return }
            switch current {
                case .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc: pop()
                default: return
            }
        }
    }

    mutating func generateAllImpliedEndTagsThoroughly() {
        while let node = stack.last, isHTMLElement(node) {
            switch name(of: node) {
                case .caption, .colgroup, .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td,
                    .tfoot, .th, .thead, .tr:
                    pop()
                default: return
            }
        }
    }

    /// "Close a p element": generate implied end tags except for `p`, then pop through the `p`.
    mutating func closeP() {
        generateImpliedEndTags(except: .p)
        popUntilHTML(.p)
    }

    /// Whether the stack has a `template` element.
    var hasTemplateOnStack: Bool { stack.contains { isHTML($0, .template) } }
}

extension HTMLTreeBuilder {
    /// The bytes of an element's local name, a doctype's name or a processing instruction's target.
    func nameBytes(of node: Node) -> ArraySlice<UInt8> {
        tokenizer.out.bytes(range: document.nameRange(node))
    }

    /// Whether the element has an attribute of this name (no namespace).
    func hasAttribute(_ node: Node, _ name: ArraySlice<UInt8>) -> Bool {
        var index = document.records[Int(node.raw)].firstAttribute
        while index >= 0 {
            let record = document.attributeRecords[Int(index)]
            if record.namespace == 0, tokenizer.out.bytes(range: record.name).elementsEqual(name) { return true }
            index = record.next
        }
        return false
    }
}

/// A set of element names as two words (the names are integers below 128): asking costs two shifts and no allocation.
struct NameSet {
    private var low: UInt64 = 0
    private var high: UInt64 = 0

    init(_ names: HTMLName...) {
        for name in names {
            if name.rawValue < 64 { low |= 1 << UInt64(name.rawValue) } else { high |= 1 << UInt64(name.rawValue - 64) }
        }
    }

    @inline(__always) func contains(_ raw: UInt16) -> Bool {
        raw < 64 ? (low >> UInt64(raw)) & 1 == 1 : (raw < 128 ? (high >> UInt64(raw - 64)) & 1 == 1 : false)
    }

    static let tableContext = NameSet(.table, .template, .html)
    static let tableBodyContext = NameSet(.tbody, .tfoot, .thead, .template, .html)
    static let tableRowContext = NameSet(.tr, .template, .html)
    static let tableTextContext = NameSet(.table, .tbody, .template, .tfoot, .thead, .tr)
    static let cells = NameSet(.td, .th)
    static let listItems = NameSet(.li)
    static let definitionItems = NameSet(.dd, .dt)
}

extension HTMLTreeBuilder {
    /// Whether `bytes` spell `word` (lower case) in any case.
    static func equalsIgnoringCase(_ bytes: ArraySlice<UInt8>, _ word: String) -> Bool {
        guard bytes.count == word.utf8.count else { return false }
        for (byte, expected) in zip(bytes, word.utf8) where lower(byte) != expected { return false }
        return true
    }

    /// Whether `bytes`, in lower case, are `lowered`.
    static func equalsLowered(_ bytes: ArraySlice<UInt8>, _ lowered: ArraySlice<UInt8>) -> Bool {
        guard bytes.count == lowered.count else { return false }
        for (byte, expected) in zip(bytes, lowered) where lower(byte) != expected { return false }
        return true
    }
}
