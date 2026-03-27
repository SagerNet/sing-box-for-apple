import Foundation

public struct UpdateInfo: Codable {
    public let versionName: String
    public let releaseURL: String
    public let downloadURL: String
    public let releaseNotes: String?
    public let isPrerelease: Bool
    public let fileSize: Int64

    public init(
        versionName: String,
        releaseURL: String,
        downloadURL: String,
        releaseNotes: String?,
        isPrerelease: Bool,
        fileSize: Int64
    ) {
        self.versionName = versionName
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.isPrerelease = isPrerelease
        self.fileSize = fileSize
    }
}
