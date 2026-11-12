internal import AemiKernel

/// The tokens of a document on one flat tape (ADR 0001): a slot is 64 bits (`TapeSlot`), a token is one or a few slots, and no token is an object. Text is never copied out of the source unless the
/// standard changes it (a character reference, a NUL, a name's case), and then it is copied once, to `scratch`; a slot says which of the two its bytes are in.
///
/// Slot shapes, by tag:
/// - `startTag`, `endTag`: `aux` is the attribute count (12 bits) and the self-closing flag (bit 12), `low` the index of the next token; then a `name` slot, then a `name` and a `value` slot per attribute.
/// - `text`, `comment`, `name`, `value`: `aux` is the length shifted left one and the scratch flag, `low` the offset in `source` or `scratch`.
/// - `processingInstruction`: `low` is the index of the next token; then a `name` slot (the target) and a `value` slot (the data).
/// - `doctype`: `aux` is the flags (`HTMLDoctypeFlags`), `low` the index of the next token; then a `name`, a public and a system `value` slot, empty when missing.
///
/// Text may come in several consecutive slots (a run of source, a decoded reference, another run); readers that want one string join them.
public struct HTMLTokens: Sendable {
    public internal(set) var source: [UInt8]
    var scratch: [UInt8] = []
    var tape = Arena<UInt64>()
    public internal(set) var errors: [Error] = []

    public struct Error: Sendable, Equatable {
        public var code: HTMLParseError
        /// The offset in `source` where the tokenizer was when it found it.
        public var offset: Int
    }

    enum Tag {
        static let startTag: UInt8 = 1
        static let endTag: UInt8 = 2
        static let text: UInt8 = 3
        static let comment: UInt8 = 4
        static let doctype: UInt8 = 5
        static let name: UInt8 = 6
        static let value: UInt8 = 7
        static let processingInstruction: UInt8 = 8
    }

    static let selfClosingFlag: UInt64 = 1 << 12
    static let maxAttributes = 4095
    /// The longest text one slot holds (27 bits); longer runs are split.
    static let maxLength = (1 << 27) - 1

    init(source: [UInt8]) { self.source = source }

    /// Tokens, in order.
    public var tokens: Tokens { Tokens(tokens: self) }

    /// The bytes of a text-shaped slot.
    func bytes(ofSlot slot: Int) -> ArraySlice<UInt8> { bytes(range: tape[slot]) }

    /// The element name the text-shaped slot spells, found without making a slice of the bytes (a slice holds its array, and holding and letting go of it showed in the profile).
    func name(ofSlot slot: Int) -> HTMLName {
        let value = tape[slot]
        let aux = Int(TapeSlot.aux(value))
        let low = TapeSlot.low(value)
        let length = aux >> 1
        guard length <= 8 else { return HTMLName.lookup(bytes(ofSlot: slot)) }
        func key(_ array: [UInt8]) -> UInt64 {
            precondition(low >= 0 && low + length <= array.count, "a name lies inside its buffer")
            return array.withUnsafeBufferPointer { buffer in
                var key: UInt64 = 0
                for offset in 0 ..< length { key = key << 8 | UInt64(unsafe buffer[low + offset]) }
                return key
            }
        }
        return HTMLName.lookup(key: aux & 1 == 0 ? key(source) : key(scratch), count: length)
    }

    /// The bytes of a slot-shaped range: `aux` is the length shifted left one and the scratch flag, `low` the offset.
    func bytes(range value: UInt64) -> ArraySlice<UInt8> { TapeRange.bytes(value, source: source, scratch: scratch) }

    /// Appends a copy of the bytes of `range` to the scratch. A range that is itself in the scratch is copied by index: a slice of the array kept while the array is appended to would make every append copy the whole array.
    mutating func appendCopy(of range: UInt64) {
        let aux = Int(TapeSlot.aux(range))
        let low = TapeSlot.low(range)
        let length = aux >> 1
        if aux & 1 == 0 {
            scratch.append(contentsOf: source[low ..< low + length])
        } else {
            for index in low ..< low + length { scratch.append(scratch[index]) }
        }
    }

    /// A range over bytes the builder adds to the scratch.
    mutating func intern(_ bytes: [UInt8]) -> UInt64 {
        let start = scratch.count
        scratch.append(contentsOf: bytes)
        return TapeSlot.make(
            tag: 0,
            aux: UInt64(Swift.min(scratch.count - start, HTMLTokens.maxLength) << 1 | 1),
            low: start
        )
    }

    /// As `intern(_:)`, for the UTF-8 of a string, byte by byte (a generic append of a string's bytes allocates).
    mutating func intern(utf8 string: String) -> UInt64 {
        let start = scratch.count
        for byte in string.utf8 { scratch.append(byte) }
        return TapeSlot.make(
            tag: 0,
            aux: UInt64(Swift.min(scratch.count - start, HTMLTokens.maxLength) << 1 | 1),
            low: start
        )
    }

    /// Whether the tape has no token.
    public var isEmpty: Bool { tape.isEmpty }

    public struct Tokens: Sequence, Sendable {
        let tokens: HTMLTokens

        public func makeIterator() -> Iterator { Iterator(tokens: tokens) }

        public struct Iterator: IteratorProtocol {
            let tokens: HTMLTokens
            var index = 0

            public mutating func next() -> HTMLToken? {
                guard index < tokens.tape.count else { return nil }
                let token = HTMLToken(tokens: tokens, index: index)
                index = token.next
                return token
            }
        }
    }
}
