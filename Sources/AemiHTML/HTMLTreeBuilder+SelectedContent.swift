/// The `selectedcontent` element (HTML Standard 4.10.x, "update a select's descendant selectedcontent elements"): in a `select` without `multiple`, an enabled `selectedcontent` holds a copy of the children of the select's selected option.
///
/// The standard does it as options are popped and attributes change; a parse that is over has one outcome, which this computes once, at the end: the selected option of each such `select` is the last with a `selected` attribute or, with none and a display size of 1, the first that
/// is not disabled; and each enabled `selectedcontent` under it (its nearest `select` ancestor, no `option` or `selectedcontent` in between) gets copies of that option's children. The work is bounded: copies stop when they would exceed the size of the document, which a hostile
/// document (one big option, a thousand `selectedcontent` elements) would otherwise square.
extension HTMLDocument {
    mutating func updateSelectedContents() {
        var budget = max(4096, records.count)
        // For each select: its selected option and the size of what is under it, found once however many selectedcontent elements it has.
        var selectedOptions: [Int32: (option: Node, size: Int)] = [:]
        let original = records.count
        for index in 0 ..< original where records[index].name == HTMLName.selectedcontent.rawValue {
            let content = Node(raw: Int32(index))
            guard records[index].namespace == Namespace.html.rawValue,
                let select = nearestSelect(ofSelectedContent: content), !hasAttribute("multiple", select)
            else { continue }
            let (option, size): (Node, Int)
            if let known = selectedOptions[select.raw] {
                (option, size) = known
            } else {
                let chosen = selectedOption(of: select)
                (option, size) = (chosen, chosen.isNone ? 0 : subtreeSize(childrenOf: chosen))
                selectedOptions[select.raw] = (option, size)
            }
            var child = firstChild(content)
            while !child.isNone {
                let next = nextSibling(child)
                detach(child)
                child = next
            }
            guard !option.isNone else { continue }
            guard size <= budget else { continue }
            budget -= size
            copyChildren(of: option, to: content)
        }
    }

    private func hasAttribute(_ name: String, _ node: Node) -> Bool { attribute(name, of: node) != nil }

    /// The `select` a `selectedcontent` belongs to: its nearest `select` ancestor, if no other `select`, no `option` and no `selectedcontent` lies between them or beyond (the standard's "disabled").
    private func nearestSelect(ofSelectedContent content: Node) -> Node? {
        var nearest = Node.none
        var ancestor = parent(content)
        var top = content
        while !ancestor.isNone {
            top = ancestor
            if records[Int(ancestor.raw)].namespace == Namespace.html.rawValue {
                switch HTMLName(rawValue: records[Int(ancestor.raw)].name) {
                    case .select:
                        guard nearest.isNone else { return nil }
                        nearest = ancestor
                    case .option, .selectedcontent: return nil
                    default: break
                }
            }
            ancestor = parent(ancestor)
        }
        // A node that was taken out of the document (by the adoption agency, say) has no document above it.
        return nearest.isNone || top != root ? nil : nearest
    }

    /// The option the select has selected once parsing is over (the selectedness setting algorithm), or none.
    private func selectedOption(of select: Node) -> Node {
        var lastSelected = Node.none
        var firstEnabled = Node.none
        for option in listOfOptions(of: select) {
            if hasAttribute("selected", option) { lastSelected = option }
            if firstEnabled.isNone, !isDisabled(option) { firstEnabled = option }
        }
        if !lastSelected.isNone { return lastSelected }
        return displaySize(of: select) == 1 ? firstEnabled : .none
    }

    /// "To get the list of options" (4.10.7): the options in tree order, not looking inside a nested `select`, `hr`, `option`, `datalist`, or an `optgroup` inside an `optgroup`.
    private func listOfOptions(of select: Node) -> [Node] {
        var options: [Node] = []
        var node = firstChild(select)
        while !node.isNone {
            var descend = true
            if kind(node) == .element, records[Int(node.raw)].namespace == Namespace.html.rawValue {
                switch HTMLName(rawValue: records[Int(node.raw)].name) {
                    case .option:
                        options.append(node)
                        descend = false
                    case .select, .hr, .datalist: descend = false
                    case .optgroup where hasOptgroupAncestor(node, below: select): descend = false
                    default: break
                }
            }
            if descend, !firstChild(node).isNone {
                node = firstChild(node)
                continue
            }
            while !node.isNone, nextSibling(node).isNone {
                node = parent(node)
                if node == select { return options }
            }
            if node.isNone { break }
            node = nextSibling(node)
        }
        return options
    }

    private func hasOptgroupAncestor(_ node: Node, below select: Node) -> Bool {
        var ancestor = parent(node)
        while !ancestor.isNone, ancestor != select {
            if records[Int(ancestor.raw)].name == HTMLName.optgroup.rawValue { return true }
            ancestor = parent(ancestor)
        }
        return false
    }

    private func isDisabled(_ option: Node) -> Bool {
        if hasAttribute("disabled", option) { return true }
        let group = parent(option)
        return !group.isNone && records[Int(group.raw)].name == HTMLName.optgroup.rawValue
            && hasAttribute("disabled", group)
    }

    /// 4.10.7: the `size` attribute if it is a positive number; else 4 with `multiple` and 1 without.
    private func displaySize(of select: Node) -> Int {
        if let size = attribute("size", of: select) {
            var value = 0
            var seen = false
            for byte in size.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0C || $0 == 0x0D }) {
                guard byte >= 0x30, byte <= 0x39, value < 1 << 20 else { break }
                value = value * 10 + Int(byte - 0x30)
                seen = true
            }
            if seen, value > 0 { return value }
        }
        return hasAttribute("multiple", select) ? 4 : 1
    }

    private func subtreeSize(childrenOf node: Node) -> Int {
        var count = 0
        for _ in descendants(of: node) { count += 1 }
        return count - 1
    }

    /// Copies the subtree below `source` under `target`: an explicit stack of (source child, new parent) pairs.
    private mutating func copyChildren(of source: Node, to target: Node) {
        var pending: [(Node, Node)] = []
        var child = lastChild(source)
        while !child.isNone {
            pending.append((child, target))
            child = previousSibling(child)
        }
        while let (original, parent) = pending.popLast() {
            let record = records[Int(original.raw)]
            let copy = makeNode(
                Kind(rawValue: record.kind) ?? .element,
                name: HTMLName(rawValue: record.name) ?? .unknown,
                space: Namespace(rawValue: record.namespace) ?? .html,
                nameRange: record.nameRange,
                dataRange: record.dataRange
            )
            var attribute = record.firstAttribute
            while attribute >= 0 {
                let found = attributeRecords[Int(attribute)]
                addAttribute(copy, name: found.name, value: found.value, namespace: found.namespace)
                attribute = found.next
            }
            append(copy, to: parent)
            var inner = lastChild(original)
            while !inner.isNone {
                pending.append((inner, copy))
                inner = previousSibling(inner)
            }
        }
    }
}
