import ArgumentParser
import Foundation

struct ReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read messages from a chat"
    )

    @Argument(help: "Name of the chat to read from (partial match supported)")
    var chat: String

    @Option(name: .shortAndLong, help: "Maximum number of messages to show")
    var limit: Int = 20

    @Flag(name: .long, help: "Show raw element info for debugging")
    var debug: Bool = false

    @Flag(name: .long, help: "Show AX traversal and retry details")
    var traceAX: Bool = false

    func run() throws {
        guard AccessibilityPermission.ensureGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()
        let runner = AXActionRunner(traceEnabled: traceAX)

        guard kakao.ensureMainWindow(timeout: 5.0, trace: { message in
            runner.log(message)
        }) != nil else {
            print("Could not find a usable KakaoTalk window.")
            throw ExitCode.failure
        }
        runner.log("read: usable window ready")

        // Find the chat window
        let chatWindow = kakao.windows.first { window in
            window.title?.localizedCaseInsensitiveContains(chat) == true
        }

        guard let window = chatWindow else {
            print("No chat window found for '\(chat)'")
            print("\nAvailable windows:")
            for (index, w) in kakao.windows.enumerated() {
                print("  [\(index)] \(w.title ?? "(untitled)")")
            }
            print("\nTip: Open the chat you want to read first.")
            throw ExitCode.failure
        }

        let windowTitle = window.title ?? chat
        print("Reading messages from: \(windowTitle)\n")

        // Find message elements
        // Messages are typically in a scroll area or list
        let scrollAreas = window.findAll(role: kAXScrollAreaRole)
        let groups = window.findAll(role: kAXGroupRole)
        runner.log("read: scrollAreas=\(scrollAreas.count), groups=\(groups.count)")

        var messageElements: [UIElement] = []

        // Look for message containers
        for scrollArea in scrollAreas {
            // Messages might be in groups or static text elements
            let texts = scrollArea.findAll(role: kAXStaticTextRole)
            let msgGroups = scrollArea.findAll(role: kAXGroupRole)

            messageElements.append(contentsOf: texts)
            messageElements.append(contentsOf: msgGroups)
        }

        // Also check groups directly
        for group in groups {
            let texts = group.findAll(role: kAXStaticTextRole)
            messageElements.append(contentsOf: texts)
        }

        if messageElements.isEmpty {
            print("No messages found in this chat.")
            print("Use 'kmsg inspect --window <n>' to explore the window structure.")
            return
        }

        // Extract and display messages
        var messages: [(sender: String?, text: String)] = []

        for element in messageElements {
            if let text = element.stringValue, !text.isEmpty {
                // Try to determine if this is a sender name or message
                // This heuristic may need adjustment based on actual KakaoTalk structure
                messages.append((sender: nil, text: text))
            }
        }

        // Remove duplicates and limit
        var seen = Set<String>()
        let uniqueMessages = messages.filter { msg in
            let key = msg.text
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        let displayMessages = Array(uniqueMessages.suffix(limit))

        print("Recent messages (\(displayMessages.count)):\n")

        for (index, msg) in displayMessages.enumerated() {
            if debug {
                print("[\(index + 1)] \(msg.text)")
            } else {
                // Clean up and format the message
                let cleanText = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanText.isEmpty {
                    print("\(cleanText)")
                    print("")
                }
            }
        }
    }
}
