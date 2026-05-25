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

public extension Sequence<String> {
    func toStringIterator() -> LibboxStringIteratorProtocol {
        StringArrayIterator(Array(self))
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
