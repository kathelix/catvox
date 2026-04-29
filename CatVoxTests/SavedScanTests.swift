import XCTest
@testable import CatVox

final class SavedScanTests: XCTestCase {
    func testAnalysisReconstructsSavedBackendPayload() {
        let scanID = UUID(uuidString: "20F37E0D-F57A-4C2F-9A8E-1D25057D6397")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scan = makeSavedScan(
            id: scanID,
            createdAt: createdAt,
            sourceType: .photos,
            personaType: CatPersona.secretAgent.rawValue
        )

        let analysis = scan.analysis

        XCTAssertEqual(analysis.id, scanID)
        XCTAssertEqual(analysis.timestamp, createdAt)
        XCTAssertEqual(analysis.primaryEmotion, "Focused")
        XCTAssertEqual(analysis.confidenceScore, 0.91, accuracy: 0.0001)
        XCTAssertEqual(analysis.analysis, "The cat is watching a target.")
        XCTAssertEqual(analysis.personaType, CatPersona.secretAgent.rawValue)
        XCTAssertEqual(analysis.catThought, "Mission parameters accepted.")
        XCTAssertEqual(analysis.ownerTip, "Offer a wand toy.")
    }

    func testSourceTypeFallsBackToRecordedForUnknownRawValue() {
        let scan = makeSavedScan(sourceType: .photos)
        scan.sourceTypeRaw = "legacy-camera-roll"

        XCTAssertEqual(scan.sourceType.rawValue, ScanSourceType.recorded.rawValue)
    }

    func testPersonaFallsBackThroughCatPersonaMapping() {
        let scan = makeSavedScan(personaType: "Unknown Persona")

        XCTAssertEqual(scan.persona, .grumpyBoss)
    }

    private func makeSavedScan(
        id: UUID = UUID(uuidString: "8DEB5762-0CE3-43AD-9C90-E2127D05E869")!,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_100),
        sourceType: ScanSourceType = .recorded,
        personaType: String = CatPersona.chaoticHunter.rawValue
    ) -> SavedScan {
        SavedScan(
            id: id,
            createdAt: createdAt,
            sourceType: sourceType,
            originalVideoRelativePath: "\(id.uuidString)/original.mov",
            thumbnailRelativePath: "\(id.uuidString)/thumbnail.jpg",
            primaryEmotion: "Focused",
            confidenceScore: 0.91,
            analysisText: "The cat is watching a target.",
            personaType: personaType,
            catThought: "Mission parameters accepted.",
            ownerTip: "Offer a wand toy."
        )
    }
}
