//
//  AudioFormatters.swift
//  Today
//
//  Shared utility functions for audio formatting
//

import Foundation

struct AudioFormatters {
    /// Formats a duration in seconds to HH:MM:SS or MM:SS format
    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Formats playback speed for display (e.g., "1x", "1.25x", "2x")
    static func formatSpeed(_ speed: Float) -> String {
        if speed.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(speed))x"
        } else {
            return String(format: "%.2fx", speed)
        }
    }
}
