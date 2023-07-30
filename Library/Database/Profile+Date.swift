import Foundation

public extension Profile {
    var lastUpdatedString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: lastUpdated!)
    }
}
