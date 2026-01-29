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

        // Activate KakaoTalk to ensure UI is accessible
        kakao.activate()

        // Give the app a moment to become active
        Thread.sleep(forTimeInterval: 0.2)

        // Try to find the chat list
        // KakaoTalk's chat list is typically in a table or list view
        guard let mainWindow = kakao.mainWindow else {
            print("Could not find KakaoTalk main window.")
            print("Make sure KakaoTalk is open and visible.")
            throw ExitCode.failure
        }

        print("Searching for chat list in KakaoTalk...\n")

        // Find elements that might be chat list items
        // Common roles: AXRow, AXCell, AXStaticText in a table/outline view
        let tables = mainWindow.findAll(role: kAXTableRole)
        let outlines = mainWindow.findAll(role: kAXOutlineRole)
        let lists = mainWindow.findAll(role: kAXListRole)

        var chatItems: [UIElement] = []

        // Check tables for rows
        for table in tables {
            let rows = table.findAll(role: kAXRowRole)
            chatItems.append(contentsOf: rows)
        }

        // Check outlines for rows
        for outline in outlines {
            let rows = outline.findAll(role: kAXRowRole)
            chatItems.append(contentsOf: rows)
        }

        // Check lists for items
        for list in lists {
            let items = list.children
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
