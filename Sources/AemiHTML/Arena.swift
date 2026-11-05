/// Storage grown by hand for the things a parse appends to millions of times: the nodes, the attributes, the tape.
///
/// An `Array` checks at every write that it is the only owner of its storage, and a struct that holds one pays for it on every access through the struct. The arena keeps its pointer, count and
/// capacity in the struct (a class would make the compiler check exclusivity of every access, and that cost more than the arrays did), and a small object that only owns the block and frees it.
///
/// A copy of the arena shares the block. That is safe where it happens: nothing writes to a finished document or token list, and one builder (or tokenizer) appends while it builds. Growing
/// allocates a new block and leaves the old one to the copies that still hold it, so a stale copy reads valid memory up to its own count.
///
/// The index is checked at every read and write (a `Node` from another document is a mistake that must trap, not read memory), so what is unsafe is the pointer arithmetic after the check and the
/// allocation.
@safe
struct Arena<Element: BitwiseCopyable>: @unchecked Sendable {
    /// Owns the block; the arena's copies hold it alive.
    @safe private final class Block: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<Element>
        init(capacity: Int) { unsafe pointer = UnsafeMutablePointer<Element>.allocate(capacity: capacity) }
        deinit { unsafe pointer.deallocate() }
    }

    private var block: Block
    // SAFETY: `block.pointer`, valid for `capacity` elements while `block` lives.
    private var base: UnsafeMutablePointer<Element>
    private(set) var count = 0
    private var capacity: Int

    init(capacity: Int = 16) {
        self.capacity = Swift.max(capacity, 16)
        block = Block(capacity: self.capacity)
        unsafe base = block.pointer
    }

    var isEmpty: Bool { count == 0 }

    subscript(index: Int) -> Element {
        @inline(__always) get {
            precondition(UInt(bitPattern: index) < UInt(bitPattern: count), "arena index out of range")
            return unsafe base[index]
        }
        @inline(__always) nonmutating set {
            precondition(UInt(bitPattern: index) < UInt(bitPattern: count), "arena index out of range")
            unsafe base[index] = newValue
        }
    }

    @inline(__always) var last: Element? { count == 0 ? nil : unsafe base[count - 1] }

    @inline(__always) mutating func append(_ element: Element) {
        if count == capacity { grow(to: capacity * 2) }
        unsafe (base + count).initialize(to: element)
        count += 1
    }

    /// Drops the last `n` elements.
    mutating func removeLast(_ n: Int = 1) {
        precondition(n >= 0 && n <= count, "arena removeLast beyond its count")
        count -= n
    }

    mutating func removeAll() { count = 0 }

    mutating func reserveCapacity(_ minimum: Int) {
        if minimum > capacity { grow(to: minimum) }
    }

    /// The elements as a buffer, for a stretch of code that does many reads and writes and checks its own indices.
    @inline(__always)
    func withUnsafeMutableBufferPointer<R>(_ body: (UnsafeMutableBufferPointer<Element>) -> R) -> R {
        unsafe body(UnsafeMutableBufferPointer(start: base, count: count))
    }

    private mutating func grow(to newCapacity: Int) {
        let fresh = Block(capacity: newCapacity)
        unsafe fresh.pointer.initialize(from: base, count: count)
        block = fresh
        unsafe base = fresh.pointer
        capacity = newCapacity
    }
}
