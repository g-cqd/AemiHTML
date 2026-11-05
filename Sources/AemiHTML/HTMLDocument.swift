internal import AemiKernel

/// A parsed document: nodes in parallel arrays linked by index (an arena), the way the tape is flat. No node is an object, nothing is recursive, and every walk is a loop. The bytes of names, text and
/// attribute values are ranges of `source` (the input) and `scratch` (what the standard changed or the builder joined), as in `HTMLTokens`.
///
/// The tree builder reparents and foster-parents nodes, which an append-only preorder array cannot do; the arena can, and `descendants` walks it in document order without a stack of its own.
public struct HTMLDocument: Sendable {
    /// A node: an index into the arena. The document itself is `root`.
    public struct Node: Hashable, Sendable {
        let raw: Int32
        static let none = Node(raw: -1)
        public var isNone: Bool { raw < 0 }
    }

    public enum Kind: UInt8, Sendable {
        case document, element, text, comment, doctype, processingInstruction
        /// The contents of a `template` element: its only child.
        case templateContents
    }

    public enum Namespace: UInt8, Sendable { case html, svg, mathml }

    public enum QuirksMode: Sendable { case noQuirks, quirks, limitedQuirks }

    /// An attribute of an element.
    public struct Attribute: Sendable {
        public var name: ArraySlice<UInt8>
        public var value: ArraySlice<UInt8>
        /// 0 none, 1 XLink, 2 XML, 3 XMLNS: the namespace of a foreign attribute; `prefix` is its prefix.
        public var namespace: UInt8
        public var prefix: String {
            switch namespace {
                case 1: "xlink"
                case 2: "xml"
                case 3: name.elementsEqual("xmlns".utf8) ? "" : "xmlns"
                default: ""
            }
        }
    }

    public internal(set) var source: [UInt8]
    var scratch: [UInt8]
    public internal(set) var quirksMode = QuirksMode.noQuirks

    /// One node: its kind, namespace and element name, its place in the tree, the ranges of its name and data, and its attributes (a linked list in `attributes`).
    struct Record {
        var kind: UInt8
        var namespace: UInt8
        var name: UInt16
        var attributeCount: UInt16 = 0
        var parent: Int32 = -1
        var firstChild: Int32 = -1
        var lastChild: Int32 = -1
        var nextSibling: Int32 = -1
        var previousSibling: Int32 = -1
        var firstAttribute: Int32 = -1
        var lastAttribute: Int32 = -1
        var nameRange: UInt64
        var dataRange: UInt64
    }

    struct AttributeRecord {
        var name: UInt64
        var value: UInt64
        var next: Int32 = -1
        var namespace: UInt8
    }

    var records = Arena<Record>()
    var attributeRecords = Arena<AttributeRecord>()

    /// The system identifier of the doctype, if the document has one.
    var systemIdentifier: UInt64 = 0
    public internal(set) var doctype = Node.none
    /// The parse errors of the tokenizer, when they were asked for (the tree builder's are not reported).
    public internal(set) var errors: [HTMLTokens.Error] = []
    /// The encoding the bytes were decoded with (`HTMLParser.parse(encoded:)`); UTF-8 for a document parsed from UTF-8 bytes.
    public internal(set) var encoding = HTMLEncoding.utf8
    /// The encoding the first `meta` that declared one named, after the standard's mapping (UTF-16 to UTF-8, x-user-defined to windows-1252); what makes a parse start again when the encoding was only a guess.
    var declaredEncoding: HTMLEncoding?
    /// For a fragment parse, the root `html` element whose children are the result.
    public internal(set) var fragmentRoot = Node.none

    public var root: Node { Node(raw: 0) }
    public var nodeCount: Int { records.count }

    init(source: [UInt8], scratch: [UInt8]) {
        self.source = source
        self.scratch = scratch
        // A page has a node for about every 24 bytes of markup.
        records.reserveCapacity(source.count / 24 + 16)
        _ = makeNode(.document)
    }

    // MARK: Reading

    public func kind(_ node: Node) -> Kind { Kind(rawValue: records[Int(node.raw)].kind) ?? .element }
    public func parent(_ node: Node) -> Node { Node(raw: records[Int(node.raw)].parent) }
    public func firstChild(_ node: Node) -> Node { Node(raw: records[Int(node.raw)].firstChild) }
    public func lastChild(_ node: Node) -> Node { Node(raw: records[Int(node.raw)].lastChild) }
    public func nextSibling(_ node: Node) -> Node { Node(raw: records[Int(node.raw)].nextSibling) }
    public func previousSibling(_ node: Node) -> Node { Node(raw: records[Int(node.raw)].previousSibling) }
    public func namespace(_ node: Node) -> Namespace { Namespace(rawValue: records[Int(node.raw)].namespace) ?? .html }

    /// The element's local name (`foreignObject` keeps its case), a doctype's name, or a processing instruction's target.
    public func name(_ node: Node) -> ArraySlice<UInt8> { bytes(records[Int(node.raw)].nameRange) }

    /// The data of a text, comment or processing instruction node.
    public func data(_ node: Node) -> ArraySlice<UInt8> { bytes(records[Int(node.raw)].dataRange) }

    public var publicIdentifier: ArraySlice<UInt8> { doctype.isNone ? [] : data(doctype) }
    public var documentSystemIdentifier: ArraySlice<UInt8> { bytes(systemIdentifier) }

    func elementName(_ node: Node) -> HTMLName { HTMLName(rawValue: records[Int(node.raw)].name) ?? .unknown }

    public func isElement(_ node: Node, _ name: String, in space: Namespace = .html) -> Bool {
        kind(node) == .element && namespace(node) == space && self.name(node).elementsEqual(name.utf8)
    }

    func bytes(_ range: UInt64) -> ArraySlice<UInt8> {
        let aux = Int(TapeSlot.aux(range))
        let low = TapeSlot.low(range)
        let length = aux >> 1
        return aux & 1 == 0 ? source[low ..< low + length] : scratch[low ..< low + length]
    }

    public func attributes(of node: Node) -> [Attribute] {
        var found: [Attribute] = []
        var index = records[Int(node.raw)].firstAttribute
        while index >= 0 {
            let record = attributeRecords[Int(index)]
            found.append(Attribute(name: bytes(record.name), value: bytes(record.value), namespace: record.namespace))
            index = record.next
        }
        return found
    }

    /// The value of the attribute `name` (no namespace), if the element has it.
    public func attribute(_ name: String, of node: Node) -> ArraySlice<UInt8>? {
        var index = records[Int(node.raw)].firstAttribute
        while index >= 0 {
            let record = attributeRecords[Int(index)]
            if record.namespace == 0, bytes(record.name).elementsEqual(name.utf8) { return bytes(record.value) }
            index = record.next
        }
        return nil
    }

    /// The nodes under `node` in document order, without recursion: the next node is the first child, else the next sibling, else the next sibling of the nearest ancestor that has one.
    public func descendants(of node: Node) -> Descendants { Descendants(document: self, start: node) }

    public struct Descendants: Sequence, IteratorProtocol {
        let document: HTMLDocument
        let start: Node
        var current = Node.none
        var started = false

        init(document: HTMLDocument, start: Node) {
            self.document = document
            self.start = start
        }

        public mutating func next() -> Node? {
            if !started {
                started = true
                current = document.firstChild(start)
                return current.isNone ? nil : current
            }
            guard !current.isNone else { return nil }
            var node = current
            let child = document.firstChild(node)
            if !child.isNone {
                current = child
                return current
            }
            while node != start {
                let sibling = document.nextSibling(node)
                if !sibling.isNone {
                    current = sibling
                    return current
                }
                node = document.parent(node)
            }
            current = .none
            return nil
        }
    }

    // MARK: Building (the tree builder's)

    mutating func makeNode(
        _ kind: Kind,
        name: HTMLName = .unknown,
        space: Namespace = .html,
        nameRange: UInt64 = 0,
        dataRange: UInt64 = 0
    ) -> Node {
        records.append(
            Record(
                kind: kind.rawValue,
                namespace: space.rawValue,
                name: name.rawValue,
                nameRange: nameRange,
                dataRange: dataRange
            )
        )
        return Node(raw: Int32(records.count - 1))
    }

    mutating func addAttribute(_ node: Node, name: UInt64, value: UInt64, namespace: UInt8 = 0) {
        let index = Int32(attributeRecords.count)
        attributeRecords.append(AttributeRecord(name: name, value: value, namespace: namespace))
        let last = records[Int(node.raw)].lastAttribute
        if last >= 0 { attributeRecords[Int(last)].next = index } else { records[Int(node.raw)].firstAttribute = index }
        records[Int(node.raw)].lastAttribute = index
        records[Int(node.raw)].attributeCount += 1
    }

    /// Puts `child` last under `parent`.
    mutating func append(_ child: Node, to parent: Node) {
        unsafe records.withUnsafeMutableBufferPointer { unsafe Self.link(child, in: parent, before: .none, $0) }
    }

    /// Puts `child` under `parent` before `reference` (last, if `reference` is none).
    mutating func insert(_ child: Node, in parent: Node, before reference: Node) {
        unsafe records.withUnsafeMutableBufferPointer { unsafe Self.link(child, in: parent, before: reference, $0) }
    }

    /// Takes `node` out of its parent.
    mutating func detach(_ node: Node) {
        unsafe records.withUnsafeMutableBufferPointer { unsafe Self.unlink(node, $0) }
    }

    // The links are changed through one pointer: an array checks, at every element it writes, that it is the only owner of its storage.
    private static func unlink(_ node: Node, _ records: UnsafeMutableBufferPointer<Record>) {
        let record = unsafe records[Int(node.raw)]
        guard record.parent >= 0 else { return }
        if record.previousSibling >= 0 {
            unsafe records[Int(record.previousSibling)].nextSibling = record.nextSibling
        } else {
            unsafe records[Int(record.parent)].firstChild = record.nextSibling
        }
        if record.nextSibling >= 0 {
            unsafe records[Int(record.nextSibling)].previousSibling = record.previousSibling
        } else {
            unsafe records[Int(record.parent)].lastChild = record.previousSibling
        }
        unsafe records[Int(node.raw)].parent = -1
        unsafe records[Int(node.raw)].previousSibling = -1
        unsafe records[Int(node.raw)].nextSibling = -1
    }

    private static func link(
        _ child: Node,
        in parent: Node,
        before reference: Node,
        _ records: UnsafeMutableBufferPointer<Record>
    ) {
        unsafe unlink(child, records)
        let previous =
            unsafe reference.isNone ? records[Int(parent.raw)].lastChild : records[Int(reference.raw)].previousSibling
        unsafe records[Int(child.raw)].parent = parent.raw
        unsafe records[Int(child.raw)].previousSibling = previous
        unsafe records[Int(child.raw)].nextSibling = reference.raw
        if reference.isNone {
            // `reference.raw` is -1: the child ends the list.
        } else {
            unsafe records[Int(reference.raw)].previousSibling = child.raw
        }
        if previous >= 0 {
            unsafe records[Int(previous)].nextSibling = child.raw
        } else {
            unsafe records[Int(parent.raw)].firstChild = child.raw
        }
        if reference.isNone { unsafe records[Int(parent.raw)].lastChild = child.raw }
    }

    /// Moves all the children of `from` to the end of `to`.
    mutating func moveChildren(of from: Node, to target: Node) {
        var child = firstChild(from)
        while !child.isNone {
            let next = nextSibling(child)
            append(child, to: target)
            child = next
        }
    }

    // MARK: Fields the builder reads often

    func atom(_ node: Node) -> UInt16 { records[Int(node.raw)].name }
    func namespaceRaw(_ node: Node) -> UInt8 { records[Int(node.raw)].namespace }
    func kindRaw(_ node: Node) -> UInt8 { records[Int(node.raw)].kind }
    func nameRange(_ node: Node) -> UInt64 { records[Int(node.raw)].nameRange }
    func dataRange(_ node: Node) -> UInt64 { records[Int(node.raw)].dataRange }
    mutating func setDataRange(_ node: Node, _ range: UInt64) { records[Int(node.raw)].dataRange = range }
}
