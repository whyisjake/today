//
//  Item.swift
//  Today
//
//  Created by Jake Spurlock on 10/22/25.
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
