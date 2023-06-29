//
//  Profile+Date.swift
//  Library
//
//  Created by 世界 on 2023/6/29.
//

import Foundation

public extension Profile {
    var lastUpdatedString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: lastUpdated!)
    }
}
