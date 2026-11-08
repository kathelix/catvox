import XCTest

final class CatVoxUITests: XCTestCase {
    /// Timeout for every wait in this suite. GitHub's macOS runners are
    /// sometimes several times slower than usual, and a 4-second wait for the
    /// source chooser timed out on one. A wait returns as soon as its element
    /// appears or disappears, so a long timeout doesn't slow down passing runs.
    private static let waitTimeout: TimeInterval = 20

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testHomeScreenSmoke() {
        launchApp()

        XCTAssertTrue(element("home.readMyCatButton").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(element("home.historyList").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(element("home.quotaStatus").waitForExistence(timeout: Self.waitTimeout))
    }

    func testSourceChoiceFlowCanBeDismissed() {
        launchApp()

        let readMyCatButton = element("home.readMyCatButton")
        XCTAssertTrue(readMyCatButton.waitForExistence(timeout: Self.waitTimeout))
        readMyCatButton.tap()

        let recordNewVideoButton = element("source.recordNewVideoButton")
        let chooseFromPhotosButton = element("source.chooseFromPhotosButton")
        let cancelButton = element("source.cancelButton")

        XCTAssertTrue(recordNewVideoButton.waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(chooseFromPhotosButton.waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: Self.waitTimeout))

        cancelButton.tap()
        XCTAssertTrue(recordNewVideoButton.waitForNonExistence(timeout: Self.waitTimeout))
    }

    func testSeededHistoryReplayOpensResultWithoutUpload() {
        launchApp(arguments: ["-seedHistory"])

        let historyItem = element("home.historyItem.0")
        XCTAssertTrue(historyItem.waitForExistence(timeout: Self.waitTimeout))
        historyItem.tap()

        XCTAssertTrue(element("result.screen").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(element("result.catThoughtText").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertFalse(element("upload.progressCard").exists)
    }

    func testMockedQuotaExceededStateRendersUpgradeUIWithoutUpload() {
        launchApp(arguments: ["-forceQuotaExceeded"])

        let readMyCatButton = element("home.readMyCatButton")
        XCTAssertTrue(readMyCatButton.waitForExistence(timeout: Self.waitTimeout))
        readMyCatButton.tap()

        XCTAssertTrue(element("quota.card").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertTrue(element("quota.upgradeButton").waitForExistence(timeout: Self.waitTimeout))
        XCTAssertFalse(element("source.recordNewVideoButton").exists)
        XCTAssertFalse(element("upload.progressCard").exists)
    }

    private func launchApp(arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockBackend"] + arguments
        app.launchEnvironment["CATVOX_DISABLE_ANALYTICS"] = "1"
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
