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

        var mainWindow = kakao.activateAndWaitForWindow()

        if mainWindow == nil {
            print("Could not find KakaoTalk main window. Opening KakaoTalk...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["/Applications/KakaoTalk.app"]
            try? process.run()
            process.waitUntilExit()

            Thread.sleep(forTimeInterval: 2.0)
            mainWindow = kakao.activateAndWaitForWindow(timeout: 5.0)
        }

        guard let mainWindow = mainWindow else {
            print("Could not find KakaoTalk main window after opening.")
            throw ExitCode.failure
        }

        print("Looking for chat with '\(recipient)'...")

        // 1. Check for existing chat window
        if let existingWindow = kakao.windows.first(where: { $0.title?.contains(recipient) == true }) {
            print("Found existing chat window.")
            try sendMessageToWindow(existingWindow)
            return
        }

        // 2. Open chat via search
        print("No existing chat window. Opening via search...")
        let chatWindow = try openChatViaSearch(recipient: recipient, in: mainWindow, kakao: kakao)

        // 3. Send message
        try sendMessageToWindow(chatWindow)
    }

    private func openChatViaSearch(recipient: String, in mainWindow: UIElement, kakao: KakaoTalkApp) throws -> UIElement {
        print("Searching for '\(recipient)'...")

        // 1. Find search field (may already be visible or need to click search button first)
        var textFields = mainWindow.findAll(role: kAXTextFieldRole)
        var searchField = textFields.first

        // If no text field found, try clicking the search button (magnifying glass)
        if searchField == nil {
            let buttons = mainWindow.findAll(role: kAXButtonRole)
            // The search button is typically one of the buttons without a title/identifier
            // Try clicking buttons that might be the search button
            for button in buttons {
                let title = button.title ?? ""
                let identifier = button.identifier ?? ""
                // Skip known navigation buttons
                if identifier == "friends" || identifier == "chatrooms" || identifier == "more" {
                    continue
                }
                // Skip buttons with specific titles
                if title == "Chats" || title == "OpenChat" || title == "Button" {
                    continue
                }
                // Try this button
                try? button.press()
                Thread.sleep(forTimeInterval: 0.3)

                textFields = mainWindow.findAll(role: kAXTextFieldRole)
                if let field = textFields.first {
                    searchField = field
                    break
                }
            }
        }

        guard let searchField = searchField else {
            throw KakaoTalkError.elementNotFound("Search field not found")
        }

        // 4. Focus search field and type query
        try searchField.focus()
        Thread.sleep(forTimeInterval: 0.1)
        typeText(recipient)
        Thread.sleep(forTimeInterval: 0.5)

        // 5. Find matching result in search results
        let results = mainWindow.findAll(role: kAXRowRole) + mainWindow.findAll(role: kAXCellRole)
        guard let matchingResult = results.first(where: { result in
            let text = result.title ?? result.stringValue ?? ""
            let staticTexts = result.findAll(role: kAXStaticTextRole)
            let hasMatch = text.contains(recipient) || staticTexts.contains {
                ($0.stringValue ?? "").contains(recipient)
            }
            return hasMatch
        }) else {
            pressEscape()
            throw KakaoTalkError.elementNotFound("No search result found for '\(recipient)'")
        }

        // 6. Click matching result
        try matchingResult.press()

        // 7. Wait for chat window to open
        let timeout: TimeInterval = 3.0
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            Thread.sleep(forTimeInterval: 0.2)

            if let window = kakao.windows.first(where: { $0.title?.contains(recipient) == true }) {
                print("Chat window opened.")
                return window
            }
        }

        throw KakaoTalkError.windowNotFound("Chat window for '\(recipient)' did not open")
    }

    private func pressEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        let escKeyCode: CGKeyCode = 53

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: escKeyCode, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: escKeyCode, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
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
