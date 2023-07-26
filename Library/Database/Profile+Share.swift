import Foundation
import Libbox

public extension Profile {
    var shareLink: URL {
        URL(string: LibboxGenerateRemoteProfileImportLink(name, remoteURL!))!
    }
}
