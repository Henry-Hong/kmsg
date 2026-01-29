import ArgumentParser
import AppKit
import Foundation

struct SendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a message to a chat"
    )

    @Argument(help: "Name of the chat or friend to send to")
    var recipient: String

    @Argument(help: "Message to send")
    var message: String

    @Flag(name: .long, help: "Don't actually send, just show what would happen")
    var dryRun: Bool = false

    func run() throws {
        guard AccessibilityPermission.isGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()

        if dryRun {
            print("Dry run mode - no message will be sent")
            print("Recipient: \(recipient)")
            print("Message: \(message)")
            return
        }

        kakao.activate()
        Thread.sleep(forTimeInterval: 0.3)

        // Find or open the chat window for the recipient
        print("Looking for chat with '\(recipient)'...")

        // First, try to find an existing chat window with this recipient
        let chatWindow = kakao.windows.first { window in
            window.title?.contains(recipient) == true
        }

        if let window = chatWindow {
            print("Found existing chat window.")
            try sendMessageToWindow(window)
        } else {
            print("No existing chat window found.")
            print("Please open a chat with '\(recipient)' first, or use the full window title.")
            print("\nAvailable windows:")
            for (index, window) in kakao.windows.enumerated() {
                print("  [\(index)] \(window.title ?? "(untitled)")")
            }
            throw ExitCode.failure
        }
    }

    private func sendMessageToWindow(_ window: UIElement) throws {
        // Find the text input field
        // This is typically an AXTextArea or AXTextField at the bottom of the chat window
        let textAreas = window.findAll(role: kAXTextAreaRole)
        let textFields = window.findAll(role: kAXTextFieldRole)

        let inputField = textAreas.last ?? textFields.last

        guard let input = inputField else {
            print("Could not find message input field.")
            print("Use 'kmsg inspect' to explore the window structure.")
            throw ExitCode.failure
        }

        // Focus the input field
        print("Focusing input field...")
        do {
            try input.focus()
            Thread.sleep(forTimeInterval: 0.1)
        } catch {
            print("Warning: Could not focus input field: \(error)")
        }

        // Type the message using keyboard simulation
        print("Typing message...")
        typeText(message)

        // Press Enter to send
        Thread.sleep(forTimeInterval: 0.1)
        print("Sending message...")
        pressEnter()

        print("✓ Message sent to '\(recipient)'")
    }

    private func typeText(_ text: String) {
        // Use CGEvent to simulate keyboard input
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            // For non-ASCII characters (like Korean), use the Unicode input method
            let string = String(char)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                var unicodeChars = Array(string.utf16)
                event.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                event.post(tap: .cghidEventTap)
            }
            // Small delay between characters
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func pressEnter() {
        let source = CGEventSource(stateID: .hidSystemState)
        let enterKeyCode: CGKeyCode = 36 // Return key

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
