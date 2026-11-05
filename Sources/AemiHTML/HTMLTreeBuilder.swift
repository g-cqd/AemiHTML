internal import AemiKernel

/// What a builder makes of a token: it is done with it, or the insertion mode changed and the same token is to be processed again (13.2.6.4: "reprocess the token").
enum Disposition {
    case consumed
    case reprocess
}

/// A token as the tree builder reads it: a view of the tokenizer's tape, with the name as an integer.
struct BuilderToken {
    enum Kind { case doctype, startTag, endTag, comment, processingInstruction, character, endOfFile }
    var kind: Kind
    /// The tape index of a tag, comment, doctype or processing instruction.
    var index = 0
    /// The name of a tag, as an integer; `unknown` for the names the standard does not mention.
    var name = HTMLName.unknown
    /// The range of a character token, or of a comment's data.
    var text: UInt64 = 0
    var selfClosing = false
    /// For a character token: a run of whitespace, of NUL, or of anything else (the builder cuts each text token into such runs).
    var characterClass = CharacterClass.other
    /// Set when the builder acknowledges the self-closing flag; a flag that was not acknowledged is a parse error the builder does not report.
    var acknowledged = false
}

enum CharacterClass { case whitespace, null, other }

/// The insertion modes (13.2.4.1).
enum InsertionMode: UInt8 {
    case initial, beforeHTML, beforeHead, inHead, inHeadNoscript, afterHead, inBody, text
    case inTable, inTableText, inCaption, inColumnGroup, inTableBody, inRow, inCell
    case inTemplate, afterBody, inFrameset, afterFrameset, afterAfterBody, afterAfterFrameset
}

/// The tree-construction stage (13.2.6): a stack of open elements, a list of active formatting elements and the insertion modes, on explicit arrays, driving the tokenizer between tokens. Every algorithm of the
/// standard that loops (the adoption agency, reconstruction, scope checks) is a loop here too; nothing is recursive, and the depth of the tree is bounded (`maxDepth`).
struct HTMLTreeBuilder {
    typealias Node = HTMLDocument.Node

    /// One entry of the list of active formatting elements: an element and the tape index of the start tag it was made for, or a marker.
    struct FormattingEntry {
        var node: Node
        var tokenIndex: Int
        var isMarker: Bool { node.isNone }
    }

    var tokenizer: HTMLTokenizer
    var document: HTMLDocument
    var mode = InsertionMode.initial
    var originalMode = InsertionMode.initial
    var templateModes: [InsertionMode] = []
    var stack: [Node] = []
    var formatting: [FormattingEntry] = []
    var headPointer = Node.none
    var formPointer = Node.none
    var framesetOK = true
    var scripting: Bool
    var fosterParenting = false
    /// Character tokens collected by the "in table text" mode: ranges, and whether any is not whitespace.
    var pendingTableText: [UInt64] = []
    var pendingTableTextHasNonWhitespace = false
    var contextElement = Node.none
    var maxDepth: Int
    var lastInsertWasLeaf = false
    /// Set after `pre`, `listing` and `textarea`: a line feed that starts the next text is dropped.
    var skipNewline = false
    /// For the one element the next `createElement` makes: a name other than the token's (an `image` start tag makes an `img`).
    var nameOverride: (HTMLName, String)?
    /// The `annotation-xml` elements whose start tag said `encoding=text/html` or `application/xhtml+xml`: HTML integration points.
    var htmlIntegrationAnnotations: Set<Int32> = []
    /// Set when a `selectedcontent` element was made: the document is given its copies of the selected option at the end.
    var sawSelectedContent = false
    var collectsErrors = false
    /// The first encoding a `meta` in the head declared (13.2.6.4.4: "change the encoding").
    var declaredEncoding: HTMLEncoding?
    var cursor = 0
    var reachedEnd = false

    init(tokenizer: HTMLTokenizer, scripting: Bool, maxDepth: Int) {
        self.tokenizer = tokenizer
        self.scripting = scripting
        self.maxDepth = maxDepth
        document = HTMLDocument(source: [], scratch: [])
        document.records.reserveCapacity(tokenizer.out.source.count / 24 + 16)
        document.attributeRecords.reserveCapacity(tokenizer.out.source.count / 48 + 16)
    }

    // MARK: The tokenizer's tokens

    /// Reads the tokens the tokenizer has made, driving it a batch at a time, and processes each (the tree construction dispatcher, 13.2.6).
    mutating func run() {
        while true {
            let adjusted = stack.isEmpty ? Node.none : adjustedCurrentNode
            tokenizer.allowsCDATA = !adjusted.isNone && space(of: adjusted) != .html
            let more = tokenizer.advance()
            readBatch()
            if tokenizer.done || !more { break }
        }
        process(BuilderToken(kind: .endOfFile))
        finish()
    }

    mutating func readBatch() {
        let count = tokenizer.out.tape.count
        while cursor < count {
            let slot = tokenizer.out.tape[cursor]
            let tag = TapeSlot.tag(slot)
            switch tag {
                case HTMLTokens.Tag.text:
                    let range = TapeSlot.make(tag: 0, aux: TapeSlot.aux(slot), low: TapeSlot.low(slot))
                    process(BuilderToken(kind: .character, text: range))
                    cursor += 1
                case HTMLTokens.Tag.comment:
                    let range = TapeSlot.make(tag: 0, aux: TapeSlot.aux(slot), low: TapeSlot.low(slot))
                    process(BuilderToken(kind: .comment, text: range))
                    cursor += 1
                case HTMLTokens.Tag.startTag, HTMLTokens.Tag.endTag:
                    let isStart = tag == HTMLTokens.Tag.startTag
                    let name = HTMLName.lookup(tokenizer.out.bytes(ofSlot: cursor + 1))
                    let closing = TapeSlot.aux(slot) & HTMLTokens.selfClosingFlag != 0
                    let token = BuilderToken(
                        kind: isStart ? .startTag : .endTag,
                        index: cursor,
                        name: name,
                        selfClosing: isStart && closing
                    )
                    let next = TapeSlot.low(slot)
                    process(token)
                    cursor = next
                case HTMLTokens.Tag.doctype:
                    let next = TapeSlot.low(slot)
                    process(BuilderToken(kind: .doctype, index: cursor))
                    cursor = next
                default:
                    let next = TapeSlot.low(slot)
                    process(BuilderToken(kind: .processingInstruction, index: cursor))
                    cursor = next
            }
        }
    }

    // MARK: Reading a token

    func tagNameBytes(_ token: BuilderToken) -> ArraySlice<UInt8> { tokenizer.out.bytes(ofSlot: token.index + 1) }

    func attributeCount(_ token: BuilderToken) -> Int { Int(TapeSlot.aux(tokenizer.out.tape[token.index]) & 0xFFF) }

    /// The value of the attribute `name` on a tag token (lower case name), if it has one.
    mutating func tokenAttribute(_ token: BuilderToken, _ name: String) -> ArraySlice<UInt8>? {
        for number in 0 ..< attributeCount(token) {
            let at = token.index + 2 + number * 2
            if tokenizer.out.bytes(ofSlot: at).elementsEqual(name.utf8) { return tokenizer.out.bytes(ofSlot: at + 1) }
        }
        return nil
    }

    mutating func tokenHasAttribute(_ token: BuilderToken, _ name: String) -> Bool {
        tokenAttribute(token, name) != nil
    }

    // MARK: Whitespace

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
    }

    /// `range` cut to `from ..< to` (offsets in the range).
    func sub(_ range: UInt64, _ from: Int, _ to: Int) -> UInt64 {
        let aux = Int(TapeSlot.aux(range))
        let isScratch = aux & 1
        return TapeSlot.make(tag: 0, aux: UInt64((to - from) << 1 | isScratch), low: TapeSlot.low(range) + from)
    }

    func length(_ range: UInt64) -> Int { Int(TapeSlot.aux(range)) >> 1 }
}
