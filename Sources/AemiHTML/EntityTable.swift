/// The HTML5 named character references (2,231 keys: the names with their semicolon, and the 106 legacy ones without), looked up by key.
///
/// The data is generated (`Generated/EntityTable+Data.swift`) and read once into a byte array and an array of line starts; a lookup is a binary search inside the range of lines that start with the
/// key's first byte.
enum EntityTable {
    private static let bytes: [UInt8] = data.withUTF8Buffer { buffer in
        // SAFETY: the buffer is the static string's own bytes, valid for the whole run of the program, and read here only to copy.
        unsafe Array(buffer)
    }

    private static let lineStarts: [Int] = {
        var starts: [Int] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            if index > start { starts.append(start) }
            start = index + 1
        }
        // The data string has no newline after its last line.
        if start < bytes.count { starts.append(start) }
        return starts
    }()

    /// For each first byte, the range of lines that start with it.
    private static let ranges: [Range<Int>] = {
        var found = [Range<Int>](repeating: 0 ..< 0, count: 256)
        var line = 0
        while line < lineStarts.count {
            let first = Int(bytes[lineStarts[line]])
            var end = line
            while end < lineStarts.count, Int(bytes[lineStarts[end]]) == first { end += 1 }
            found[first] = line ..< end
            line = end
        }
        return found
    }()

    /// The code points of a reference: one, or two for a few.
    struct Entity {
        var first: UInt32
        var second: UInt32?
    }

    /// The code points of `key` (the name, with its `;` if it has one), or nil.
    static func lookup(in input: [UInt8], start: Int, length: Int) -> Entity? {
        guard length >= 2, length <= longestName else { return nil }
        let range = ranges[Int(input[start])]
        var low = range.lowerBound
        var high = range.upperBound - 1
        while low <= high {
            let middle = (low + high) / 2
            let order = compare(input, start, length, at: lineStarts[middle])
            if order == 0 { return entity(at: lineStarts[middle] + length + 1) }
            if order < 0 { high = middle - 1 } else { low = middle + 1 }
        }
        return nil
    }

    private static func compare(_ key: [UInt8], _ keyStart: Int, _ length: Int, at start: Int) -> Int {
        var index = 0
        while index < length {
            let entry = bytes[start + index]
            if entry == 0x20 { return 1 }
            let byte = key[keyStart + index]
            if byte != entry { return byte < entry ? -1 : 1 }
            index += 1
        }
        return bytes[start + length] == 0x20 ? 0 : -1
    }

    private static func entity(at start: Int) -> Entity {
        var first: UInt32 = 0
        var second: UInt32?
        var value: UInt32 = 0
        var index = start
        while index < bytes.count, bytes[index] != 0x0A {
            let byte = bytes[index]
            if byte == 0x20 {
                first = value
                second = 0
                value = 0
            } else {
                value = value * 16 + UInt32(byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10)
            }
            index += 1
        }
        if second != nil { return Entity(first: first, second: value) }
        return Entity(first: value, second: nil)
    }
}
