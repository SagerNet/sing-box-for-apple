import Foundation
import Libbox
import NetworkExtension

func runBlocking<T>(_ body: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = resultBox<T>()
    Task {
        do {
            let value = try await body()
            box.result = .success(value)
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private class resultBox<T> {
    var result: Result<T, Error>!
}
