import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check KakaoTalk and accessibility status"
    )

    @Flag(name: .long, help: "Show detailed information")
    var verbose: Bool = false

    func run() throws {
        print("kmsg - KakaoTalk CLI Tool\n")

        // Check accessibility permission
        let hasPermission = AccessibilityPermission.isGranted()
        print("Accessibility Permission: \(hasPermission ? "✓ Granted" : "✗ Not Granted")")

        if !hasPermission {
            print("")
            AccessibilityPermission.printInstructions()
            return
        }

        // Check KakaoTalk status
        let isRunning = KakaoTalkApp.isRunning
        print("KakaoTalk: \(isRunning ? "✓ Running" : "✗ Not Running")")

        if !isRunning {
            print("\nPlease launch KakaoTalk to continue.")
            return
        }

        // Get detailed info if verbose
        if verbose {
            print("")
            do {
                let kakao = try KakaoTalkApp()
                let windows = kakao.windows

                print("Windows (\(windows.count)):")
                for (index, window) in windows.enumerated() {
                    let title = window.title ?? "(untitled)"
                    let frame = window.frame.map { "(\(Int($0.origin.x)), \(Int($0.origin.y))) \(Int($0.size.width))x\(Int($0.size.height))" } ?? "unknown"
                    print("  [\(index)] \(title) - \(frame)")
                }
            } catch {
                print("Error accessing KakaoTalk: \(error)")
            }
        }

        print("\n✓ Ready to use kmsg commands")
    }
}
