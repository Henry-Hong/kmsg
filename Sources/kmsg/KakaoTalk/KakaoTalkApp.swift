import AppKit
import Foundation

/// Represents the KakaoTalk application and provides access to its UI elements
public final class KakaoTalkApp: Sendable {
    public static let bundleIdentifier = "com.kakao.KakaoTalkMac"

    private let app: UIElement

    public init(autoLaunch: Bool = true) throws {
        if Self.runningApplication == nil && autoLaunch {
            guard Self.launch() != nil else {
                throw KakaoTalkError.launchFailed
            }
        }

        guard let runningApp = Self.runningApplication else {
            throw KakaoTalkError.appNotRunning
        }

        self.app = UIElement.application(pid: runningApp.processIdentifier)
    }

    // MARK: - App State

    /// Check if KakaoTalk is currently running
    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Get the running KakaoTalk application
    public static var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    /// Launch KakaoTalk application
    /// - Parameter timeout: Maximum time to wait for app to launch (default: 5 seconds)
    /// - Returns: The running application if launched successfully
    @discardableResult
    public static func launch(timeout: TimeInterval = 5.0) -> NSRunningApplication? {
        if let app = runningApplication {
            return app
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if let app = runningApplication {
                return app
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        return runningApplication
    }

    /// Activate KakaoTalk (bring to foreground)
    public func activate() {
        guard let app = Self.runningApplication else { return }

        // Unhide the app first if it's hidden
        if app.isHidden {
            app.unhide()
        }

        // Use activateIgnoringOtherApps to reliably bring to foreground
        app.activate(options: [.activateIgnoringOtherApps])
    }

    /// Activate KakaoTalk and wait for the main window to be available
    /// - Parameter timeout: Maximum time to wait for the window (default: 2 seconds)
    /// - Returns: The main window if available within the timeout, nil otherwise
    public func activateAndWaitForWindow(timeout: TimeInterval = 2.0) -> UIElement? {
        activate()

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if let window = mainWindow {
                return window
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        return mainWindow
    }

    // MARK: - Windows

    /// Get all KakaoTalk windows
    public var windows: [UIElement] {
        app.windows
    }

    /// Get the main window (friends list)
    public var mainWindow: UIElement? {
        app.mainWindow
    }

    /// Get the focused window
    public var focusedWindow: UIElement? {
        app.focusedWindow
    }

    // MARK: - Window Discovery

    /// Find a window by its title
    public func findWindow(title: String) -> UIElement? {
        windows.first { $0.title == title }
    }

    /// Find a window containing the given title substring
    public func findWindow(titleContaining substring: String) -> UIElement? {
        windows.first { $0.title?.contains(substring) == true }
    }

    /// Get the friends list window
    public var friendsWindow: UIElement? {
        // The main KakaoTalk window typically shows the user's name or "친구" in the title
        mainWindow ?? windows.first
    }

    /// Get the chat list window
    public var chatListWindow: UIElement? {
        // Chat list might be a separate window or tab within main window
        findWindow(titleContaining: "채팅") ?? mainWindow
    }

    // MARK: - UI Navigation

    /// Get the application element for direct traversal
    public var applicationElement: UIElement {
        app
    }

    // MARK: - Debug

    /// Print the UI hierarchy for debugging
    public func printHierarchy(maxDepth: Int = 3) {
        print("KakaoTalk UI Hierarchy:")
        printElement(app, depth: 0, maxDepth: maxDepth)
    }

    private func printElement(_ element: UIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)
        print("\(indent)\(element.debugDescription)")

        for child in element.children {
            printElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

// MARK: - Errors

public enum KakaoTalkError: Error, CustomStringConvertible {
    case appNotRunning
    case launchFailed
    case windowNotFound(String)
    case elementNotFound(String)
    case actionFailed(String)
    case permissionDenied

    public var description: String {
        switch self {
        case .appNotRunning:
            return "KakaoTalk is not running. Please launch KakaoTalk first."
        case .launchFailed:
            return "Failed to launch KakaoTalk. Please launch it manually."
        case .windowNotFound(let name):
            return "Window not found: \(name)"
        case .elementNotFound(let description):
            return "UI element not found: \(description)"
        case .actionFailed(let action):
            return "Action failed: \(action)"
        case .permissionDenied:
            return "Accessibility permission denied. Please grant permission in System Settings."
        }
    }
}
