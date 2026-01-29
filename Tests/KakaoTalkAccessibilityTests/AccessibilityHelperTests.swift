import XCTest
@testable import KakaoTalkAccessibility

final class AccessibilityHelperTests: XCTestCase {
    func testAccessibilityStatusCheck() {
        // This test just verifies the function can be called
        // The actual result depends on system permissions
        _ = AccessibilityHelper.checkAccessibilityStatus()
    }

    func testKakaoTalkRunningCheck() {
        // This test just verifies the function can be called
        // The actual result depends on whether KakaoTalk is running
        _ = KakaoTalkApp.isRunning()
    }
}
