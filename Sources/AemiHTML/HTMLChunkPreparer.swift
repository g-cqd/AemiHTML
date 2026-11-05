/// What `HTMLTokenizer.prepared(_:)` does to a whole input, done to pieces of it: the byte order mark dropped, ill-formed UTF-8 repaired, line endings normalized. The pieces are cut anywhere, so what cannot be settled yet waits for the next one: the start of a
/// multi-byte sequence at the end, a CR (which may be the first half of a CR LF), and the first bytes of the stream while a byte order mark is still possible. The bytes returned, concatenated, are exactly what `prepared` makes of the pieces joined.
struct HTMLChunkPreparer {
    private var held: [UInt8] = []
    private var atStart = true
    let dropsByteOrderMark: Bool

    init(dropsByteOrderMark: Bool) { self.dropsByteOrderMark = dropsByteOrderMark }

    /// The bytes of `chunk` that are settled, and `final`: that no more will come, so nothing waits.
    mutating func prepare(_ chunk: [UInt8], final: Bool) -> [UInt8] {
        var bytes = held.isEmpty ? chunk : held + chunk
        held = []
        if atStart {
            // Three bytes decide whether there is a byte order mark.
            if bytes.count < 3, !final, !chunk.isEmpty || !bytes.isEmpty {
                held = bytes
                return []
            }
            atStart = false
            if dropsByteOrderMark, bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                bytes.removeFirst(3)
            }
        }
        if !final {
            let tail = Self.incompleteTail(bytes)
            if tail > 0 {
                held = Array(bytes.suffix(tail))
                bytes.removeLast(tail)
            }
            if held.isEmpty, bytes.last == 0x0D {
                held = [0x0D]
                bytes.removeLast()
            }
        }
        return HTMLTokenizer.prepared(bytes, dropsByteOrderMark: false)
    }

    /// How many bytes at the end are the start of a multi-byte sequence that is not complete yet (0 to 3).
    static func incompleteTail(_ bytes: [UInt8]) -> Int {
        let count = bytes.count
        var back = 1
        while back <= 3, back <= count {
            let byte = bytes[count - back]
            if byte & 0xC0 == 0x80 {
                back += 1
                continue
            }
            let needed = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : (byte >= 0xC0 ? 2 : 1))
            return needed > back ? back : 0
        }
        return 0
    }
}
