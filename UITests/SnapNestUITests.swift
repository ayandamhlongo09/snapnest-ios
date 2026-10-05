import XCTest

@MainActor
final class SnapNestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testCaptureOfflineThenReconnectAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        app.buttons["Demo controls"].tap()
        let offline = app.switches["Go offline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        offline.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(offline.value as? String, "1")
        let countLabel = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'unique photos accepted'")).firstMatch
        for _ in 0..<3 { if countLabel.exists { break }; app.swipeUp() }
        let initialCount = try XCTUnwrap(Int(countLabel.label.split(separator: " ").first.map(String.init) ?? ""))
        app.buttons["Done"].tap()
        app.buttons["Choose photo"].tap()
        // Recent OS releases host the library picker outside the app process.
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photo-picker")
        let photo = picker.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        if photo.waitForExistence(timeout: 3) {
            photo.tap()
        } else {
            // iOS 27's out-of-process picker omits its grid from XCTest's app snapshot.
            // This fallback targets the first tile in the inspected normal-text 3-column grid.
            // The setup must import demo-document.png last so that tile is synthetic.
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Native library before selecting synthetic first tile"; attachment.lifetime = .keepAlways
            add(attachment)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.40)).tap()
        }
        XCTAssertTrue(app.staticTexts["Saved · Waiting to send"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Demo controls"].tap()
        offline.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(offline.value as? String, "0")
        app.buttons["Done"].tap()
        // Restoring demo connectivity must send without requiring a relaunch.
        XCTAssertTrue(app.staticTexts["Sent"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Demo controls"].tap()
        XCTAssertTrue(app.staticTexts["\(initialCount + 1) unique photos accepted"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Sent"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Demo controls"].tap()
        XCTAssertTrue(app.staticTexts["\(initialCount + 1) unique photos accepted"].waitForExistence(timeout: 10))
    }
    func testDemoOfflineCanBeDisabledRepeatedly() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        for _ in 0..<2 {
            app.buttons["Demo controls"].tap()
            let offline = app.switches["Go offline"]
            XCTAssertTrue(offline.waitForExistence(timeout: 10))
            offline.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(offline.value as? String, "1")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Demo offline mode is on. Turn it off in Demo controls to send photos."].waitForExistence(timeout: 5))
            app.buttons["Demo controls"].tap()
            offline.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(offline.value as? String, "0")
            app.buttons["Done"].tap()
            let demoBanner = app.staticTexts["Demo offline mode is on. Turn it off in Demo controls to send photos."]
            XCTAssertFalse(demoBanner.waitForExistence(timeout: 2))
        }
    }
    func testLargeTextCaptureButtonsRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Identity document"].waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if app.buttons["Choose photo"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Choose photo"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Maximum Dynamic Type"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
