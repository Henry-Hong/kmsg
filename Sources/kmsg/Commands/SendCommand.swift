import ArgumentParser
import Foundation
import KakaoTalkAccessibility

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a message to a KakaoTalk chat"
    )

    @Argument(help: "The message to send")
    var message: String

    @Option(name: .shortAndLong, help: "Name of the chat room to send to (searches current chats)")
    var chat: String?

    @Flag(name: .long, help: "Use send button instead of Enter key")
    var useSendButton: Bool = false

    @Flag(name: .long, help: "Dry run - don't actually send, just show what would happen")
    var dryRun: Bool = false

    func run() throws {
        let app = try KakaoTalkApp()

        if let chatName = chat {
            // Send to a specific chat room
            print("Looking for chat room: \(chatName)")

            guard let chatRoom = try app.findChatRoom(named: chatName) else {
                print("Error: Chat room '\(chatName)' not found.")
                print("Make sure the chat is visible in your chat list.")
                throw ExitCode.failure
            }

            print("Found chat: \(chatRoom.name)")

            if dryRun {
                print()
                print("[Dry run] Would send to '\(chatRoom.name)': \(message)")
                return
            }

            print("Opening chat...")
            try app.openChatRoom(chatRoom)

            // Wait for chat window to open
            Thread.sleep(forTimeInterval: 0.3)

            print("Sending message...")
            try app.sendMessage(message, useSendButton: useSendButton)

            print("Message sent!")
        } else {
            // Send to the currently open chat
            if dryRun {
                print("[Dry run] Would send to current chat: \(message)")
                return
            }

            print("Sending message to current chat...")
            try app.sendMessage(message, useSendButton: useSendButton)

            print("Message sent!")
        }
    }
}
