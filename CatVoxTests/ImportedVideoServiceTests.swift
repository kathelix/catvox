import XCTest
@testable import CatVox

final class ImportedVideoServiceTests: XCTestCase {
    func testValidationErrorMessagesMatchCanonicalCopy() {
        XCTAssertEqual(
            ImportedVideoValidationError.tooLong.errorDescription,
            "This video is longer than 10 seconds. Please choose a shorter clip."
        )
        XCTAssertEqual(
            ImportedVideoValidationError.tooLarge.errorDescription,
            "This video is larger than 100 MB. Please choose a smaller clip."
        )
        XCTAssertEqual(
            ImportedVideoValidationError.proResUnsupported.errorDescription,
            "ProRes videos aren't supported."
        )
        XCTAssertEqual(
            ImportedVideoValidationError.unsupportedFormat.errorDescription,
            "This video format isn't supported."
        )
        XCTAssertEqual(
            ImportedVideoValidationError.importFailed.errorDescription,
            "We couldn't import this video. Please try another clip."
        )
    }

    func testMimeTypeMapsSupportedContainers() {
        XCTAssertEqual(
            ImportedVideoService.mimeType(for: URL(fileURLWithPath: "/tmp/cat.mov")),
            "video/quicktime"
        )
        XCTAssertEqual(
            ImportedVideoService.mimeType(for: URL(fileURLWithPath: "/tmp/cat.mp4")),
            "video/mp4"
        )
        XCTAssertEqual(
            ImportedVideoService.mimeType(for: URL(fileURLWithPath: "/tmp/cat.m4v")),
            "video/x-m4v"
        )
    }
}
