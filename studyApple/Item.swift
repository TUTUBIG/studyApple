//
//  Item.swift
//  studyApple
//
//  Created by Alvin liu on 2024/4/25.
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
