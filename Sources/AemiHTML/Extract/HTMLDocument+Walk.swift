extension HTMLDocument {
    /// A step of a walk in document order: a node is entered, then (after its children) exited. A text or comment node is entered and exited at once.
    public enum WalkEvent: Sendable, Equatable {
        case enter(Node)
        case exit(Node)
    }

    /// Walks the nodes under `root` as enter and exit events, with no recursion and no stack of its own: from a node the next step is its first child, else its exit, and from an exit the next sibling, else the exit of the parent.
    /// `skipChildren()` after an `enter` passes over the subtree (the exit still follows).
    public struct Walker {
        let document: HTMLDocument
        let root: Node
        var current: Node
        var exiting = false
        var lastEntered = Node.none

        init(document: HTMLDocument, root: Node) {
            self.document = document
            self.root = root
            current = document.firstChild(root)
        }

        public mutating func next() -> WalkEvent? {
            guard !current.isNone else { return nil }
            if !exiting {
                let node = current
                lastEntered = node
                let child = document.firstChild(node)
                if child.isNone { exiting = true } else { current = child }
                return .enter(node)
            }
            let node = current
            let sibling = document.nextSibling(node)
            if !sibling.isNone {
                current = sibling
                exiting = false
            } else {
                let parent = document.parent(node)
                current = parent == root ? .none : parent
                exiting = true
            }
            return .exit(node)
        }

        /// After an `enter`: do not walk into the node's children.
        public mutating func skipChildren() {
            guard !lastEntered.isNone else { return }
            current = lastEntered
            exiting = true
        }
    }

    public func walk(_ root: Node) -> Walker { Walker(document: self, root: root) }
}
