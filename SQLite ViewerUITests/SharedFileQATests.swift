import XCTest

final class SharedFileQATests: XCTestCase {
    @MainActor
    func testInspectFilesShare() throws {
        let viewer = XCUIApplication()
        viewer.launch()
        viewer.terminate()
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        sleep(3)
        XCTFail(files.debugDescription)
    }
}
