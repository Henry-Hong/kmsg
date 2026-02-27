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

    @Flag(name: .long, help: "Show AX traversal and retry details")
    var traceAX: Bool = false

    func run() throws {
        guard AccessibilityPermission.ensureGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()
        let runner = AXActionRunner(traceEnabled: traceAX)

        // Prefer the chat list window ("카카오톡") over any conversation window
        let mainWindow: UIElement
        if let chatListWindow = kakao.chatListWindow {
            mainWindow = chatListWindow
            runner.log("chats: using chatListWindow title='\(chatListWindow.title ?? "")'")
        } else if let fallback = kakao.ensureMainWindow(timeout: 5.0, trace: { message in
            runner.log(message)
        }) {
            mainWindow = fallback
            runner.log("chats: fallback to ensureMainWindow")
        } else {
            print("Could not find a usable KakaoTalk window.")
            throw ExitCode.failure
        }

        runner.log("chats: usable window ready")
        print("Searching for chat list in KakaoTalk...\n")

        // Find elements that might be chat list items
        // Common roles: AXRow, AXCell, AXStaticText in a table/outline view
        // Use limit to enable early termination and avoid full UI tree scan
        let tables = mainWindow.findAll(role: kAXTableRole, limit: 1)
        let outlines = mainWindow.findAll(role: kAXOutlineRole, limit: 1)
        let lists = mainWindow.findAll(role: kAXListRole, limit: 1)
        runner.log("chats: tables=\(tables.count), outlines=\(outlines.count), lists=\(lists.count)")

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
            runner.log("chats: no chat items found after traversal")
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
        if let title = element.title, !title.isEmpty {
            return title
        }

        let staticTexts = element.findAll(role: kAXStaticTextRole)
        for text in staticTexts {
            let identifier = text.identifier ?? ""
            // Skip unread count badge (id: "Count Label")
            if identifier == "Count Label" { continue }
            guard let value = text.stringValue, !value.isEmpty else { continue }
            // Skip time-like values (e.g. "21:59", "15:19")
            if isTimeLikeValue(value) { continue }
            // Skip pure numeric or "999+" style unread counts
            if value.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "," }) { continue }
            return value
        }

        return "(Unknown Chat)"
    }

    private func extractLastMessage(from element: UIElement) -> String? {
        // KakaoTalk 26.x: last message is in AXTextArea inside AXScrollArea
        let textAreas = element.findAll(role: kAXTextAreaRole)
        for textArea in textAreas {
            if let value = textArea.stringValue, !value.isEmpty {
                return value
            }
        }
        // Fallback: second static text that isn't count/time
        let staticTexts = element.findAll(role: kAXStaticTextRole)
        if staticTexts.count > 1 {
            return staticTexts[1].stringValue
        }
        return nil
    }

    private func isTimeLikeValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        if parts.count == 2,
           parts[0].count <= 2, parts[1].count == 2,
           parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber)
        {
            return true
        }
        // Date-like values (e.g. "2월 27일", "어제")
        if trimmed.hasSuffix("일") || trimmed == "어제" || trimmed == "그저께" {
            return true
        }
        return false
    }
}
