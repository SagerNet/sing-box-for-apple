import Foundation
import Libbox
import Network

public class NWSocket {
    private let connection: NWConnection

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public func read() throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { content, _, _, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(content!)
            }
            semaphore.signal()
        }
        semaphore.wait()
        let lengthChunk = try result.get()
        let length = Int(LibboxDecodeLengthChunk(lengthChunk))
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { content, _, _, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(content!)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    public func write(_ data: Data?) throws {
        guard let data else {
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Error?
        connection.send(content: LibboxEncodeChunkedMessage(data), isComplete: false, completion: .contentProcessed { error in
            result = error
            semaphore.wait()
        })
        if let result {
            throw result
        }
    }

    public func send(_ data: Data?) {
        guard let data else {
            return
        }
        connection.send(content: LibboxEncodeChunkedMessage(data), completion: .idempotent)
    }

    public func cancel() {
        connection.cancel()
    }
}
