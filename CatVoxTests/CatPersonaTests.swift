import XCTest
@testable import CatVox

final class CatPersonaTests: XCTestCase {
    func testRawValuesMatchTRDPersonaLabels() {
        let expectedRawValues: [CatPersona: String] = [
            .grumpyBoss: "The Grumpy Boss",
            .existentialPhilosopher: "The Existential Philosopher",
            .dramaticDiva: "The Dramatic Diva",
            .secretAgent: "The Secret Agent",
            .chaoticHunter: "The Chaotic Hunter",
            .affectionateSweetheart: "The Affectionate Sweetheart",
        ]

        XCTAssertEqual(CatPersona.allCases.count, expectedRawValues.count)

        for (persona, expectedRawValue) in expectedRawValues {
            XCTAssertEqual(persona.rawValue, expectedRawValue)
            XCTAssertEqual(CatPersona.from(expectedRawValue), persona)
        }
    }

    func testDisplayNamesKeepAPIFriendlyRawValuesSeparateFromShortUILabels() {
        XCTAssertEqual(CatPersona.grumpyBoss.displayName, "Grumpy Boss")
        XCTAssertEqual(CatPersona.existentialPhilosopher.displayName, "Existential Philosopher")
        XCTAssertEqual(CatPersona.dramaticDiva.displayName, "Dramatic Diva")
        XCTAssertEqual(CatPersona.secretAgent.displayName, "Secret Agent")
        XCTAssertEqual(CatPersona.chaoticHunter.displayName, "Chaotic Hunter")
        XCTAssertEqual(CatPersona.affectionateSweetheart.displayName, "Affectionate Sweetheart")
    }

    func testUnknownBackendPersonaFallsBackToGrumpyBoss() {
        XCTAssertEqual(CatPersona.from("The Suspicious Loaf"), .grumpyBoss)
    }
}
