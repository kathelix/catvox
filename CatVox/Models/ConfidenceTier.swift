import SwiftUI

enum ConfidenceTier: Equatable {
    case high
    case moderate
    case low

    static func from(score: Double) -> ConfidenceTier {
        if score > 0.80 {
            return .high
        }

        if score >= 0.50 {
            return .moderate
        }

        return .low
    }

    var color: Color {
        switch self {
        case .high:
            return Color(red: 0.22, green: 0.85, blue: 0.50)
        case .moderate:
            return Color(red: 1.00, green: 0.65, blue: 0.15)
        case .low:
            return Color(red: 0.90, green: 0.22, blue: 0.22)
        }
    }
}
