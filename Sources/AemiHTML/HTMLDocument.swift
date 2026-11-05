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

    var kinds: [UInt8] = []
    var names: [UInt16] = []
    var namespaces: [UInt8] = []
    var parents: [Int32] = []
    var firstChildren: [Int32] = []
    var lastChildren: [Int32] = []
    var nextSiblings: [Int32] = []
    var previousSiblings: [Int32] = []
    /// The name (element, doctype, processing instruction target) and the data (text, comment, processing instruction data, doctype public identifier), as slot-shaped ranges.
    var nameRanges: [UInt64] = []
    var dataRanges: [UInt64] = []
    var firstAttributes: [Int32] = []
    var lastAttributes: [Int32] = []
    var attributeCounts: [UInt16] = []
    // The attributes, linked per element so that they can be added after the element was made.
    var attributeNames: [UInt64] = []
    var attributeValues: [UInt64] = []
    var attributeNamespaces: [UInt8] = []
    var attributeNext: [Int32] = []

    /// The system identifier of the doctype, if the document has one.
    var systemIdentifier: UInt64 = 0
    public internal(set) var doctype = Node.none
    /// The parse errors of the tokenizer, when they were asked for (the tree builder's are not reported).
    public internal(set) var errors: [HTMLTokens.Error] = []
    /// For a fragment parse, the root `html` element whose children are the result.
    public internal(set) var fragmentRoot = Node.none

    public var root: Node { Node(raw: 0) }
    public var nodeCount: Int { kinds.count }

    init(source: [UInt8], scratch: [UInt8]) {
        self.source = source
        self.scratch = scratch
        _ = makeNode(.document)
    }

    // MARK: Reading

    public func kind(_ node: Node) -> Kind { Kind(rawValue: kinds[Int(node.raw)]) ?? .element }
    public func parent(_ node: Node) -> Node { Node(raw: parents[Int(node.raw)]) }
    public func firstChild(_ node: Node) -> Node { Node(raw: firstChildren[Int(node.raw)]) }
    public func lastChild(_ node: Node) -> Node { Node(raw: lastChildren[Int(node.raw)]) }
    public func nextSibling(_ node: Node) -> Node { Node(raw: nextSiblings[Int(node.raw)]) }
    public func previousSibling(_ node: Node) -> Node { Node(raw: previousSiblings[Int(node.raw)]) }
    public func namespace(_ node: Node) -> Namespace { Namespace(rawValue: namespaces[Int(node.raw)]) ?? .html }

    /// The element's local name (`foreignObject` keeps its case), a doctype's name, or a processing instruction's target.
    public func name(_ node: Node) -> ArraySlice<UInt8> { bytes(nameRanges[Int(node.raw)]) }

    /// The data of a text, comment or processing instruction node.
    public func data(_ node: Node) -> ArraySlice<UInt8> { bytes(dataRanges[Int(node.raw)]) }

    public var publicIdentifier: ArraySlice<UInt8> { doctype.isNone ? [] : data(doctype) }
    public var documentSystemIdentifier: ArraySlice<UInt8> { bytes(systemIdentifier) }

    func elementName(_ node: Node) -> HTMLName { HTMLName(rawValue: names[Int(node.raw)]) ?? .unknown }

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
        var index = firstAttributes[Int(node.raw)]
        while index >= 0 {
            found.append(
                Attribute(
                    name: bytes(attributeNames[Int(index)]),
                    value: bytes(attributeValues[Int(index)]),
                    namespace: attributeNamespaces[Int(index)]
                )
            )
            index = attributeNext[Int(index)]
        }
        return found
    }

    /// The value of the attribute `name` (no namespace), if the element has it.
    public func attribute(_ name: String, of node: Node) -> ArraySlice<UInt8>? {
        var index = firstAttributes[Int(node.raw)]
        while index >= 0 {
            if attributeNamespaces[Int(index)] == 0,
                bytes(attributeNames[Int(index)]).elementsEqual(name.utf8)
            {
                return bytes(attributeValues[Int(index)])
            }
            index = attributeNext[Int(index)]
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
        kinds.append(kind.rawValue)
        names.append(name.rawValue)
        namespaces.append(space.rawValue)
        parents.append(-1)
        firstChildren.append(-1)
        lastChildren.append(-1)
        nextSiblings.append(-1)
        previousSiblings.append(-1)
        nameRanges.append(nameRange)
        dataRanges.append(dataRange)
        firstAttributes.append(-1)
        lastAttributes.append(-1)
        attributeCounts.append(0)
        return Node(raw: Int32(kinds.count - 1))
    }

    mutating func addAttribute(_ node: Node, name: UInt64, value: UInt64, namespace: UInt8 = 0) {
        let index = Int32(attributeNames.count)
        attributeNames.append(name)
        attributeValues.append(value)
        attributeNamespaces.append(namespace)
        attributeNext.append(-1)
        let last = lastAttributes[Int(node.raw)]
        if last >= 0 { attributeNext[Int(last)] = index } else { firstAttributes[Int(node.raw)] = index }
        lastAttributes[Int(node.raw)] = index
        attributeCounts[Int(node.raw)] += 1
    }

    /// Whether the element has an attribute of this name (no namespace).
    func hasAttribute(_ node: Node, _ name: ArraySlice<UInt8>) -> Bool {
        var index = firstAttributes[Int(node.raw)]
        while index >= 0 {
            if attributeNamespaces[Int(index)] == 0, bytes(attributeNames[Int(index)]).elementsEqual(name) {
                return true
            }
            index = attributeNext[Int(index)]
        }
        return false
    }

    /// Puts `child` last under `parent`.
    mutating func append(_ child: Node, to parent: Node) {
        detach(child)
        let last = lastChildren[Int(parent.raw)]
        parents[Int(child.raw)] = parent.raw
        previousSiblings[Int(child.raw)] = last
        nextSiblings[Int(child.raw)] = -1
        if last >= 0 { nextSiblings[Int(last)] = child.raw } else { firstChildren[Int(parent.raw)] = child.raw }
        lastChildren[Int(parent.raw)] = child.raw
    }

    /// Puts `child` under `parent` before `reference` (last, if `reference` is none).
    mutating func insert(_ child: Node, in parent: Node, before reference: Node) {
        guard !reference.isNone else { return append(child, to: parent) }
        detach(child)
        let previous = previousSiblings[Int(reference.raw)]
        parents[Int(child.raw)] = parent.raw
        previousSiblings[Int(child.raw)] = previous
        nextSiblings[Int(child.raw)] = reference.raw
        previousSiblings[Int(reference.raw)] = child.raw
        if previous >= 0 { nextSiblings[Int(previous)] = child.raw } else { firstChildren[Int(parent.raw)] = child.raw }
    }

    /// Takes `node` out of its parent.
    mutating func detach(_ node: Node) {
        let parent = parents[Int(node.raw)]
        guard parent >= 0 else { return }
        let previous = previousSiblings[Int(node.raw)]
        let next = nextSiblings[Int(node.raw)]
        if previous >= 0 { nextSiblings[Int(previous)] = next } else { firstChildren[Int(parent)] = next }
        if next >= 0 { previousSiblings[Int(next)] = previous } else { lastChildren[Int(parent)] = previous }
        parents[Int(node.raw)] = -1
        previousSiblings[Int(node.raw)] = -1
        nextSiblings[Int(node.raw)] = -1
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
}
