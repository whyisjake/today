//
//  TimeIntervalExtension.swift
//  Today
//
//  Utilities for formatting time intervals
//

import Foundation

extension TimeInterval {
    /// Format time interval as MM:SS string
    /// - Returns: Formatted string in the format "M:SS" or "MM:SS"
    func formatted() -> String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
