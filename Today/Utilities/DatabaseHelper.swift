//
//  DatabaseHelper.swift
//  Today
//
//  Utilities for managing the database
//

import Foundation
import SwiftData

extension ModelContext {
    /// Clear all data from the database (useful for development/debugging)
    func clearAllData() throws {
        // Delete all articles
        try self.delete(model: Article.self)

        // Delete all feeds
        try self.delete(model: Feed.self)

        try self.save()
    }
}
