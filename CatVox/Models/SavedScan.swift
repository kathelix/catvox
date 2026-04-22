import Foundation
import SwiftData

enum ScanSourceType: String, Codable {
    case recorded
    case photos
}

@Model
final class SavedScan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var sourceTypeRaw: String
    var originalVideoRelativePath: String
    var thumbnailRelativePath: String
    var primaryEmotion: String
    var confidenceScore: Double
    var analysisText: String
    var personaType: String
    var catThought: String
    var ownerTip: String

    init(
        id: UUID,
        createdAt: Date,
        sourceType: ScanSourceType,
        originalVideoRelativePath: String,
        thumbnailRelativePath: String,
        primaryEmotion: String,
        confidenceScore: Double,
        analysisText: String,
        personaType: String,
        catThought: String,
        ownerTip: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceTypeRaw = sourceType.rawValue
        self.originalVideoRelativePath = originalVideoRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.primaryEmotion = primaryEmotion
        self.confidenceScore = confidenceScore
        self.analysisText = analysisText
        self.personaType = personaType
        self.catThought = catThought
        self.ownerTip = ownerTip
    }

    var sourceType: ScanSourceType {
        ScanSourceType(rawValue: sourceTypeRaw) ?? .recorded
    }

    var persona: CatPersona {
        CatPersona.from(personaType)
    }

    var analysis: CatAnalysis {
        CatAnalysis(
            id: id,
            primaryEmotion: primaryEmotion,
            confidenceScore: confidenceScore,
            analysis: analysisText,
            personaType: personaType,
            catThought: catThought,
            ownerTip: ownerTip,
            timestamp: createdAt
        )
    }
}
