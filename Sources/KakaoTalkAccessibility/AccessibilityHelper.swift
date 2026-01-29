import ApplicationServices
import AppKit
import Foundation

/// Helper class for working with macOS Accessibility APIs
public final class AccessibilityHelper {

    /// Check if accessibility access is enabled for this application
    public static func isAccessibilityEnabled() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Check accessibility status without prompting
    public static func checkAccessibilityStatus() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Get the accessibility element for a running application by bundle identifier
    public static func getApplicationElement(bundleIdentifier: String) throws -> AXUIElement {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else {
            throw AccessibilityError.kakaoTalkNotRunning
        }

        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// Get all windows for an application element
    public static func getWindows(for app: AXUIElement) throws -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows
    }

    /// Get the main window for an application element
    public static func getMainWindow(for app: AXUIElement) throws -> AXUIElement? {
        var mainWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &mainWindowRef)

        guard result == .success, let mainWindow = mainWindowRef else {
            return nil
        }

        return (mainWindow as! AXUIElement)
    }

    /// Get the focused window for an application element
    public static func getFocusedWindow(for app: AXUIElement) throws -> AXUIElement? {
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)

        guard result == .success, let focusedWindow = focusedWindowRef else {
            return nil
        }

        return (focusedWindow as! AXUIElement)
    }

    /// Get an attribute value from an accessibility element
    public static func getAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)

        guard result == .success, let value = valueRef as? T else {
            return nil
        }

        return value
    }

    /// Get the title of an accessibility element
    public static func getTitle(of element: AXUIElement) -> String? {
        return getAttribute(kAXTitleAttribute as String, from: element)
    }

    /// Get the value of an accessibility element
    public static func getValue(of element: AXUIElement) -> String? {
        return getAttribute(kAXValueAttribute as String, from: element)
    }

    /// Get the role of an accessibility element
    public static func getRole(of element: AXUIElement) -> String? {
        return getAttribute(kAXRoleAttribute as String, from: element)
    }

    /// Get the role description of an accessibility element
    public static func getRoleDescription(of element: AXUIElement) -> String? {
        return getAttribute(kAXRoleDescriptionAttribute as String, from: element)
    }

    /// Get the identifier of an accessibility element
    public static func getIdentifier(of element: AXUIElement) -> String? {
        return getAttribute(kAXIdentifierAttribute as String, from: element)
    }

    /// Get children of an accessibility element
    public static func getChildren(of element: AXUIElement) -> [AXUIElement] {
        return getAttribute(kAXChildrenAttribute as String, from: element) ?? []
    }

    /// Set the value of an accessibility element
    public static func setValue(_ value: String, for element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)

        guard result == .success else {
            throw AccessibilityError.actionFailed("Failed to set value")
        }
    }

    /// Perform an action on an accessibility element
    public static func performAction(_ action: String, on element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, action as CFString)

        guard result == .success else {
            throw AccessibilityError.actionFailed("Failed to perform action: \(action)")
        }
    }

    /// Press/click an element
    public static func press(_ element: AXUIElement) throws {
        try performAction(kAXPressAction as String, on: element)
    }

    /// Find children with a specific role
    public static func findChildren(of element: AXUIElement, withRole role: String) -> [AXUIElement] {
        let children = getChildren(of: element)
        return children.filter { getRole(of: $0) == role }
    }

    /// Recursively find all elements matching a predicate
    public static func findElements(
        in element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool,
        maxDepth: Int = 10
    ) -> [AXUIElement] {
        var results: [AXUIElement] = []

        if predicate(element) {
            results.append(element)
        }

        guard maxDepth > 0 else { return results }

        let children = getChildren(of: element)
        for child in children {
            results.append(contentsOf: findElements(in: child, matching: predicate, maxDepth: maxDepth - 1))
        }

        return results
    }

    /// Find the first element matching a predicate
    public static func findFirstElement(
        in element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool,
        maxDepth: Int = 10
    ) -> AXUIElement? {
        if predicate(element) {
            return element
        }

        guard maxDepth > 0 else { return nil }

        let children = getChildren(of: element)
        for child in children {
            if let found = findFirstElement(in: child, matching: predicate, maxDepth: maxDepth - 1) {
                return found
            }
        }

        return nil
    }

    /// Print the accessibility hierarchy for debugging
    public static func printHierarchy(of element: AXUIElement, indent: Int = 0, maxDepth: Int = 5) {
        guard maxDepth > 0 else { return }

        let prefix = String(repeating: "  ", count: indent)
        let role = getRole(of: element) ?? "unknown"
        let title = getTitle(of: element)
        let value = getValue(of: element)
        let identifier = getIdentifier(of: element)

        var description = "\(prefix)[\(role)]"
        if let title = title, !title.isEmpty {
            description += " title=\"\(title)\""
        }
        if let value = value, !value.isEmpty {
            description += " value=\"\(value)\""
        }
        if let identifier = identifier, !identifier.isEmpty {
            description += " id=\"\(identifier)\""
        }
        print(description)

        let children = getChildren(of: element)
        for child in children {
            printHierarchy(of: child, indent: indent + 1, maxDepth: maxDepth - 1)
        }
    }
}
