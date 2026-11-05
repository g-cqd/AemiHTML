/// The nodes of a document in document order, as flat arrays: for each, where its subtree ends and how deep it is.
///
/// The arena links nodes (parent, first child, next sibling), which suits building and walking one subtree. A question about many subtrees (how much text is under each element, how much of it is in links) is a walk per subtree there, and
/// the walks overlap. In preorder a subtree is a range of indices, so such sums are prefix sums: one pass to build the view, one to sum, then any subtree is two lookups. Built without recursion, in time linear in the nodes reachable from the root.
public struct HTMLPreorder: Sendable {
    /// The nodes, the root first, each before its children and after its previous siblings' subtrees.
    public let nodes: [HTMLDocument.Node]
    /// For the node at index `i`, the index one past the last node of its subtree: its descendants are `i + 1 ..< subtreeEnd[i]`.
    public let subtreeEnd: [Int32]
    /// The number of ancestors of the node at index `i` (the root has none).
    public let depth: [Int32]
    private let parents: [Int32]
    /// For each node of the arena, its index here, or -1 if it is not reachable from the root (a node taken out of the tree).
    private let positions: [Int32]

    public var count: Int { nodes.count }

    /// The index of `node` in this view, or nil if it is not under the root.
    public func index(of node: HTMLDocument.Node) -> Int? {
        guard node.raw >= 0, Int(node.raw) < positions.count else { return nil }
        let position = positions[Int(node.raw)]
        return position < 0 ? nil : Int(position)
    }

    /// The descendants of the node at `index`, as a range of indices.
    public func descendants(of index: Int) -> Range<Int> { index + 1 ..< Int(subtreeEnd[index]) }

    /// The subtree of the node at `index` including the node, as a range of indices.
    public func subtree(of index: Int) -> Range<Int> { index ..< Int(subtreeEnd[index]) }

    /// The index of the parent of the node at `index` (nil for the root).
    public func parentIndex(of index: Int) -> Int? {
        let parent = parents[index]
        return parent < 0 ? nil : Int(parent)
    }

    init(_ document: HTMLDocument) {
        var nodes: [HTMLDocument.Node] = []
        var ends: [Int32] = []
        var depths: [Int32] = []
        var parentIndices: [Int32] = []
        var positions = [Int32](repeating: -1, count: document.nodeCount)
        nodes.reserveCapacity(document.nodeCount)
        ends.reserveCapacity(document.nodeCount)
        depths.reserveCapacity(document.nodeCount)
        parentIndices.reserveCapacity(document.nodeCount)
        // The indices of the nodes whose subtrees are still open: the path from the root to the node being visited.
        var open: [Int32] = []

        func visit(_ node: HTMLDocument.Node) {
            positions[Int(node.raw)] = Int32(nodes.count)
            parentIndices.append(open.last ?? -1)
            open.append(Int32(nodes.count))
            depths.append(Int32(open.count - 1))
            nodes.append(node)
            ends.append(0)
        }

        let root = document.root
        visit(root)
        var current = root
        walking: while true {
            let child = document.firstChild(current)
            if !child.isNone {
                current = child
                visit(current)
                continue
            }
            // A node with no children ends here; so does each ancestor that has no next sibling.
            var node = current
            while true {
                ends[Int(open.removeLast())] = Int32(nodes.count)
                if node == root { break walking }
                let sibling = document.nextSibling(node)
                if !sibling.isNone {
                    current = sibling
                    visit(current)
                    continue walking
                }
                node = document.parent(node)
            }
        }
        self.nodes = nodes
        subtreeEnd = ends
        depth = depths
        parents = parentIndices
        self.positions = positions
    }
}

extension HTMLDocument {
    /// The nodes under the root in document order, as flat arrays with subtree ends (see `HTMLPreorder`).
    public func preorder() -> HTMLPreorder { HTMLPreorder(self) }
}
