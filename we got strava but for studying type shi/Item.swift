//
//  Item.swift
//  we got strava but for studying type shi
//
//  Created by Max on 7/11/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
