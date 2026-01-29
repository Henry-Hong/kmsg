import ApplicationServices.HIServices
import Foundation

/// Handles macOS Accessibility permission checking and requesting
public enum AccessibilityPermission {
    /// Check if the app has accessibility permissions
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user to grant accessibility permissions if not already granted
    /// Returns true if permissions are already granted
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Print instructions for granting accessibility permissions
    public static func printInstructions() {
        print("""
        ⚠️  Accessibility permission required!

        To use kmsg, you need to grant Accessibility permissions:

        1. Open System Settings > Privacy & Security > Accessibility
        2. Click the '+' button
        3. Navigate to and select the kmsg binary
        4. Enable the toggle for kmsg

        Alternatively, run: sudo kmsg --request-permission
        """)
    }
}
