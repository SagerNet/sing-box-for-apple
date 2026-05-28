import Foundation
import Libbox

public extension LibboxStringIteratorProtocol {
    func toArray() -> [String] {
        var array: [String] = []
        while hasNext() {
            array.append(next())
        }
        return array
    }
}

public extension LibboxInt32IteratorProtocol {
    func toArray() -> [Int32] {
        var array: [Int32] = []
        while hasNext() {
            array.append(next())
        }
        return array
    }
}

public extension Sequence<String> {
    func toStringIterator() -> LibboxStringIteratorProtocol {
        StringArrayIterator(Array(self))
    }
}

public extension Sequence<Int32> {
    func toInt32Iterator() -> LibboxInt32IteratorProtocol {
        Int32ArrayIterator(Array(self))
    }
}

private final class StringArrayIterator: NSObject, LibboxStringIteratorProtocol {
    private let array: [String]
    private var index: Int = 0
    private var nextValue: String = ""

    init(_ array: [String]) {
        self.array = array
    }

    func len() -> Int32 {
        Int32(array.count - index)
    }

    func hasNext() -> Bool {
        guard index < array.count else { return false }
        nextValue = array[index]
        index += 1
        return true
    }

    func next() -> String {
        nextValue
    }
}

private final class Int32ArrayIterator: NSObject, LibboxInt32IteratorProtocol {
    private let array: [Int32]
    private var index: Int = 0
    private var nextValue: Int32 = 0

    init(_ array: [Int32]) {
        self.array = array
    }

    func len() -> Int32 {
        Int32(array.count - index)
    }

    func hasNext() -> Bool {
        guard index < array.count else { return false }
        nextValue = array[index]
        index += 1
        return true
    }

    func next() -> Int32 {
        nextValue
    }
}
