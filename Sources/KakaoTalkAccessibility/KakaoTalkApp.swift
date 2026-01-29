import ApplicationServices
import AppKit
import Foundation

/// KakaoTalk bundle identifier
public let kakaoTalkBundleIdentifier = "com.kakao.KakaoTalkMac"

/// Main class for interacting with KakaoTalk via Accessibility APIs
public final class KakaoTalkApp {
    private let appElement: AXUIElement

    /// Initialize with a running KakaoTalk instance
    public init() throws {
        guard AccessibilityHelper.checkAccessibilityStatus() else {
            _ = AccessibilityHelper.isAccessibilityEnabled()
            throw AccessibilityError.accessibilityNotEnabled
        }

        self.appElement = try AccessibilityHelper.getApplicationElement(bundleIdentifier: kakaoTalkBundleIdentifier)
    }

    /// Check if KakaoTalk is currently running
    public static func isRunning() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: kakaoTalkBundleIdentifier).isEmpty
    }

    /// Activate KakaoTalk (bring to front)
    public func activate() throws {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: kakaoTalkBundleIdentifier
        ).first else {
            throw AccessibilityError.kakaoTalkNotRunning
        }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// Get all windows
    public func getWindows() throws -> [AXUIElement] {
        return try AccessibilityHelper.getWindows(for: appElement)
    }

    /// Get the main window
    public func getMainWindow() throws -> AXUIElement? {
        return try AccessibilityHelper.getMainWindow(for: appElement)
    }

    /// Print the UI hierarchy for debugging
    public func printUIHierarchy(maxDepth: Int = 5) throws {
        print("=== KakaoTalk UI Hierarchy ===")
        AccessibilityHelper.printHierarchy(of: appElement, maxDepth: maxDepth)
    }

    /// Get the raw application element for advanced operations
    public var element: AXUIElement {
        return appElement
    }
}
