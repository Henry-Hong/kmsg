import ArgumentParser
import Foundation

struct ChatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chats",
        abstract: "List chat rooms"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Maximum number of chats to show")
    var limit: Int = 20

    func run() throws {
        guard AccessibilityPermission.isGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()

        // Activate KakaoTalk and wait for the main window to be available
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

        print("Searching for chat list in KakaoTalk...\n")

        // Find elements that might be chat list items
        // Common roles: AXRow, AXCell, AXStaticText in a table/outline view
        // Use limit to enable early termination and avoid full UI tree scan
        let tables = mainWindow.findAll(role: kAXTableRole, limit: 1)
        let outlines = mainWindow.findAll(role: kAXOutlineRole, limit: 1)
        let lists = mainWindow.findAll(role: kAXListRole, limit: 1)

        var chatItems: [UIElement] = []

        // Check tables for rows
        for table in tables {
            let remaining = limit - chatItems.count
            if remaining <= 0 { break }
            let rows = table.findAll(role: kAXRowRole, limit: remaining)
            chatItems.append(contentsOf: rows)
        }

        // Check outlines for rows
        for outline in outlines {
            let remaining = limit - chatItems.count
            if remaining <= 0 { break }
            let rows = outline.findAll(role: kAXRowRole, limit: remaining)
            chatItems.append(contentsOf: rows)
        }

        // Check lists for items
        for list in lists {
            let remaining = limit - chatItems.count
            if remaining <= 0 { break }
            let items = Array(list.children.prefix(remaining))
            chatItems.append(contentsOf: items)
        }

        if chatItems.isEmpty {
            print("No chat list found.")
            print("\nTip: Make sure you're on the 'Chats' (채팅) tab in KakaoTalk.")
            print("Use 'kmsg inspect' to explore the UI structure.")
            return
        }

        print("Found \(min(chatItems.count, limit)) chat(s):\n")

        for (index, item) in chatItems.prefix(limit).enumerated() {
            let title = extractChatTitle(from: item)
            let lastMessage = extractLastMessage(from: item)

            print("[\(index + 1)] \(title)")
            if verbose, let msg = lastMessage {
                print("    └─ \(msg)")
            }
        }

        if chatItems.count > limit {
            print("\n... and \(chatItems.count - limit) more chats")
        }
    }

    private func extractChatTitle(from element: UIElement) -> String {
        // Try to find the chat name from various possible locations
        if let title = element.title, !title.isEmpty {
            return title
        }

        // Look for static text elements that might contain the name
        let staticTexts = element.findAll(role: kAXStaticTextRole)
        for text in staticTexts {
            if let value = text.stringValue, !value.isEmpty {
                return value
            }
        }

        return "(Unknown Chat)"
    }

    private func extractLastMessage(from element: UIElement) -> String? {
        // Find additional static text that might be the last message
        let staticTexts = element.findAll(role: kAXStaticTextRole)
        if staticTexts.count > 1 {
            return staticTexts[1].stringValue
        }
        return nil
    }
}
