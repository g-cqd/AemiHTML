internal import AemiKernel

/// A slot-shaped range of bytes (ADR 0001): `aux` is the length shifted left one and the scratch flag, `low` the offset.
enum TapeRange {
    /// The bytes `value` names, in `source` or, with the scratch flag, in `scratch`.
    @inline(__always)
    static func bytes(_ value: UInt64, source: [UInt8], scratch: [UInt8]) -> ArraySlice<UInt8> {
        let aux = Int(TapeSlot.aux(value))
        let low = TapeSlot.low(value)
        let length = aux >> 1
        return aux & 1 == 0 ? source[low ..< low + length] : scratch[low ..< low + length]
    }
}
