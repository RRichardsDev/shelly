//
//  Item.swift
//  Shelly
//
//  Created by Rhodri Richards on 16/12/2025.
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
