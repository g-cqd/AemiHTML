internal import AemiKernel

/// What a doctype token is missing or forces.
public struct HTMLDoctypeFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hasName = HTMLDoctypeFlags(rawValue: 1)
    public static let hasPublicIdentifier = HTMLDoctypeFlags(rawValue: 2)
    public static let hasSystemIdentifier = HTMLDoctypeFlags(rawValue: 4)
    public static let forcesQuirks = HTMLDoctypeFlags(rawValue: 8)
}

/// One token, a view of the tape: nothing is copied until a property that returns bytes is read.
public struct HTMLToken: Sendable {
    public enum Kind: Sendable, Equatable { case startTag, endTag, text, comment, doctype, processingInstruction }

    let tokens: HTMLTokens
    let index: Int

    private var slot: UInt64 { tokens.tape[index] }
    private var tag: UInt8 { TapeSlot.tag(slot) }

    public var kind: Kind {
        switch tag {
            case HTMLTokens.Tag.startTag: .startTag
            case HTMLTokens.Tag.endTag: .endTag
            case HTMLTokens.Tag.comment: .comment
            case HTMLTokens.Tag.doctype: .doctype
            case HTMLTokens.Tag.processingInstruction: .processingInstruction
            default: .text
        }
    }

    /// The index of the token after this one.
    var next: Int {
        switch tag {
            case HTMLTokens.Tag.startTag, HTMLTokens.Tag.endTag, HTMLTokens.Tag.doctype,
                HTMLTokens.Tag.processingInstruction:
                TapeSlot.low(slot)
            default: index + 1
        }
    }

    /// The text of a text or comment token (one slot of it).
    public var text: ArraySlice<UInt8> { tokens.bytes(ofSlot: index) }

    /// The data of a processing instruction (its target is `name`).
    public var data: ArraySlice<UInt8> { tokens.bytes(ofSlot: index + 2) }

    /// The name of a tag (lower case), of a doctype, or the target of a processing instruction.
    public var name: ArraySlice<UInt8> { tokens.bytes(ofSlot: index + 1) }

    public var isSelfClosing: Bool { TapeSlot.aux(slot) & HTMLTokens.selfClosingFlag != 0 }

    public var attributeCount: Int { Int(TapeSlot.aux(slot) & 0xFFF) }

    /// The attributes of a tag, in source order, the first of a repeated name only.
    public var attributes: [(name: ArraySlice<UInt8>, value: ArraySlice<UInt8>)] {
        (0 ..< attributeCount)
            .map { number in
                let at = index + 2 + number * 2
                return (tokens.bytes(ofSlot: at), tokens.bytes(ofSlot: at + 1))
            }
    }

    public var doctypeFlags: HTMLDoctypeFlags { HTMLDoctypeFlags(rawValue: Int(TapeSlot.aux(slot))) }
    public var publicIdentifier: ArraySlice<UInt8> { tokens.bytes(ofSlot: index + 2) }
    public var systemIdentifier: ArraySlice<UInt8> { tokens.bytes(ofSlot: index + 3) }
}
