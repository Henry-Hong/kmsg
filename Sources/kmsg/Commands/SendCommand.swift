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

        guard let mainWindow = kakao.activateAndWaitForWindow() else {
            print("Could not find KakaoTalk main window.")
            throw ExitCode.failure
        }

        print("Looking for chat with '\(recipient)'...")

        // 1. Check for existing chat window
        if let existingWindow = kakao.windows.first(where: { $0.title?.contains(recipient) == true }) {
            print("Found existing chat window.")
            try sendMessageToWindow(existingWindow)
            return
        }

        // 2. Search in chat list
        print("No existing chat window. Searching in chat list...")

        guard let chatItem = findChatInList(recipient: recipient, in: mainWindow) else {
            print("Could not find '\(recipient)' in the chat list.")
            print("\nTip: Make sure you're on the 'Chats' (채팅) tab in KakaoTalk.")
            print("Use 'kmsg chats' to see available chats.")
            throw ExitCode.failure
        }

        // 3. Open chat from list
        let chatWindow = try openChatFromList(chatItem: chatItem, recipient: recipient, kakao: kakao)

        // 4. Send message
        try sendMessageToWindow(chatWindow)
    }

    private func findChatInList(recipient: String, in mainWindow: UIElement) -> UIElement? {
        let tables = mainWindow.findAll(role: kAXTableRole, limit: 1)
        let outlines = mainWindow.findAll(role: kAXOutlineRole, limit: 1)
        let lists = mainWindow.findAll(role: kAXListRole, limit: 1)

        var chatItems: [UIElement] = []

        for table in tables {
            chatItems.append(contentsOf: table.findAll(role: kAXRowRole))
        }
        for outline in outlines {
            chatItems.append(contentsOf: outline.findAll(role: kAXRowRole))
        }
        for list in lists {
            chatItems.append(contentsOf: list.children)
        }

        return chatItems.first { item in
            let title = extractChatTitle(from: item)
            return title.contains(recipient)
        }
    }

    private func extractChatTitle(from element: UIElement) -> String {
        if let title = element.title, !title.isEmpty {
            return title
        }

        let staticTexts = element.findAll(role: kAXStaticTextRole)
        for text in staticTexts {
            if let value = text.stringValue, !value.isEmpty {
                return value
            }
        }

        return ""
    }

    private func openChatFromList(chatItem: UIElement, recipient: String, kakao: KakaoTalkApp) throws -> UIElement {
        print("Opening chat with '\(recipient)' from chat list...")

        do {
            try chatItem.press()
        } catch {
            try chatItem.focus()
            Thread.sleep(forTimeInterval: 0.1)
            pressEnter()
        }

        // Wait for chat window to open
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
