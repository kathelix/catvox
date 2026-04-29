import XCTest
@testable import CatVox

final class CatAnalysisTests: XCTestCase {
    func testDecodesBackendPayloadUsingSnakeCaseKeys() throws {
        let payload = """
        {
          "primary_emotion": "Territorial Alertness",
          "confidence_score": 0.87,
          "analysis": "The cat is focused on a nearby sound.",
          "persona_type": "The Grumpy Boss",
          "cat_thought": "Security standards are slipping.",
          "owner_tip": "Offer a short play session."
        }
        """

        let beforeDecode = Date()
        let analysis = try JSONDecoder().decode(
            CatAnalysis.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(analysis.primaryEmotion, "Territorial Alertness")
        XCTAssertEqual(analysis.confidenceScore, 0.87, accuracy: 0.0001)
        XCTAssertEqual(analysis.analysis, "The cat is focused on a nearby sound.")
        XCTAssertEqual(analysis.personaType, CatPersona.grumpyBoss.rawValue)
        XCTAssertEqual(analysis.catThought, "Security standards are slipping.")
        XCTAssertEqual(analysis.ownerTip, "Offer a short play session.")
        XCTAssertGreaterThanOrEqual(analysis.timestamp, beforeDecode)
    }

    func testEncodesOnlyBackendSchemaFields() throws {
        let analysis = CatAnalysis(
            id: UUID(uuidString: "8E2B7731-D650-49B4-A801-730406312E0C")!,
            primaryEmotion: "Relaxed",
            confidenceScore: 0.64,
            analysis: "The cat is calm.",
            personaType: CatPersona.affectionateSweetheart.rawValue,
            catThought: "This sun patch is acceptable.",
            ownerTip: "Slow-blink back.",
            timestamp: Date(timeIntervalSince1970: 1_234_567)
        )

        let data = try JSONEncoder().encode(analysis)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), [
            "primary_emotion",
            "confidence_score",
            "analysis",
            "persona_type",
            "cat_thought",
            "owner_tip",
        ])
        XCTAssertNil(object["id"])
        XCTAssertNil(object["timestamp"])
        XCTAssertEqual(object["primary_emotion"] as? String, "Relaxed")
        let confidenceScore = try XCTUnwrap(object["confidence_score"] as? Double)
        XCTAssertEqual(confidenceScore, 0.64, accuracy: 0.0001)
    }
}
