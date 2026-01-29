import ArgumentParser
import Foundation
import KakaoTalkAccessibility

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check KakaoTalk and accessibility status"
    )

    func run() throws {
        print("Checking status...")
        print()

        // Check accessibility
        let accessibilityEnabled = AccessibilityHelper.checkAccessibilityStatus()
        if accessibilityEnabled {
            print("[OK] Accessibility access is enabled")
        } else {
            print("[!] Accessibility access is NOT enabled")
            print("    Please enable it in System Settings > Privacy & Security > Accessibility")
            _ = AccessibilityHelper.isAccessibilityEnabled()
        }

        // Check if KakaoTalk is running
        let isRunning = KakaoTalkApp.isRunning()
        if isRunning {
            print("[OK] KakaoTalk is running")
        } else {
            print("[!] KakaoTalk is NOT running")
            print("    Please start KakaoTalk first")
        }

        // Try to connect if both checks pass
        if accessibilityEnabled && isRunning {
            print()
            print("Attempting to connect to KakaoTalk...")
            do {
                let app = try KakaoTalkApp()
                let windows = try app.getWindows()
                print("[OK] Successfully connected to KakaoTalk")
                print("     Found \(windows.count) window(s)")
            } catch {
                print("[!] Failed to connect: \(error.localizedDescription)")
            }
        }
    }
}
