import XCTest

/// Walks the app like a person: allow photos, wait for sorting, peek and open folders, open a photo, search.
final class WalkTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func allowPhotosIfAsked() {
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: label == "Allow Full Access" ? 8 : 2) { b.tap(); return }
        }
    }

    func testWalk() {
        continueAfterFailure = true
        app.launch()
        let allow = app.buttons["Allow Photo Access"]
        if allow.waitForExistence(timeout: 8) {
            shot("00-welcome")
            allow.tap()
            allowPhotosIfAsked()
        }

        let sortingBanner = app.staticTexts["Sorting your photos on this iPhone"]
        if sortingBanner.waitForExistence(timeout: 20) {
            pause(3)
            shot("01-sorting")
        }
        let done = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'sorted on this iPhone'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 600), "sorting never finished")
        pause(3)
        shot("02-folders")
        app.swipeUp()
        pause(1.5)
        shot("03-folders-more")
        app.swipeDown()
        app.swipeDown()
        pause(1)

        // Peek into the first folder before opening it.
        let firstFolder = app.scrollViews.firstMatch.buttons.firstMatch
        XCTAssertTrue(firstFolder.waitForExistence(timeout: 5))
        firstFolder.press(forDuration: 1.3)
        pause(2.5)
        shot("04-folder-peek")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        pause(1.5)

        // Open it, then its first group.
        firstFolder.tap()
        pause(2.5)
        shot("05-folder-open")
        let groupTiles = app.scrollViews.firstMatch.buttons
        if groupTiles.count > 1 {
            groupTiles.element(boundBy: 1).press(forDuration: 1.3)
            pause(2)
            shot("06-group-peek")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            pause(1.5)
            groupTiles.element(boundBy: 1).tap()
            pause(2.5)
            shot("07-group-open")
        }

        // Open a photo and ask what the app saw in it.
        let photo = app.scrollViews.firstMatch.buttons.firstMatch
        if photo.waitForExistence(timeout: 5) {
            photo.tap()
            pause(2.5)
            shot("08-photo")
            let info = app.buttons["What the app saw"]
            if info.waitForExistence(timeout: 3) {
                info.tap()
                pause(1.5)
                shot("09-photo-info")
            }
            app.swipeLeft()
            pause(1.5)
            shot("10-photo-next")
            let close = app.buttons["Close"]
            if close.exists { close.tap() }
            pause(1.5)
        }
        for _ in 0..<4 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.label != "Settings" else { break }
            back.tap()
            pause(1)
        }

        // Search in plain words.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for (i, q) in ["dog", "puppies on the grass", "mountain lake", "beahc", "food last month"].enumerated() {
            search.tap()
            if let current = search.value as? String, !current.isEmpty, current != search.placeholderValue {
                let clear = search.buttons["Clear text"]
                if clear.exists { clear.tap() } else {
                    search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
                }
            }
            search.typeText(q)
            pause(2.5)
            shot(String(format: "%02d-search-%@", 11 + i, q.replacingOccurrences(of: " ", with: "-")))
        }
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() }
        pause(1)

        // Make your own folder by describing it.
        app.buttons["New folder"].tap()
        let name = app.textFields["folderName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("My dogs")
        let describe = app.textFields["folderDescription"]
        describe.tap()
        describe.typeText("dogs")
        pause(3)
        shot("16-new-folder")
        app.buttons["Save"].tap()
        pause(3)
        shot("17-your-folders")
        let mine = app.scrollViews.firstMatch.buttons.containing(NSPredicate(format: "label BEGINSWITH 'My dogs'")).firstMatch
        if mine.waitForExistence(timeout: 5) {
            mine.tap()
            pause(2.5)
            shot("18-your-folder-open")
            app.buttons["Folder options"].tap()
            pause(1)
            app.buttons["Edit folder"].tap()
            pause(2.5)
            shot("19-edit-folder")
            app.buttons["Cancel"].tap()
            pause(1)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(1)
        }

        app.buttons["Settings"].tap()
        pause(2)
        shot("20-settings")
    }
}
