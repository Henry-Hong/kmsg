import ArgumentParser
import Foundation
import KakaoTalkAccessibility

struct Chats: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List chat rooms from KakaoTalk"
    )

    @Option(name: .shortAndLong, help: "Maximum number of chat rooms to display")
    var limit: Int = 20

    @Flag(name: .shortAndLong, help: "Show detailed information including last message")
    var verbose: Bool = false

    func run() throws {
        let app = try KakaoTalkApp()

        print("Fetching chat rooms...")
        print()

        let chatRooms = try app.getChatRooms(limit: limit)

        if chatRooms.isEmpty {
            print("No chat rooms found.")
            print()
            print("Note: Make sure the chat list is visible in KakaoTalk.")
            print("      You may need to click on the chat tab first.")
            return
        }

        print("Found \(chatRooms.count) chat room(s):")
        print()

        for (index, chatRoom) in chatRooms.enumerated() {
            if verbose {
                print("[\(index + 1)] \(chatRoom.name)")
                if let lastMessage = chatRoom.lastMessage {
                    print("    Last: \(lastMessage)")
                }
                print()
            } else {
                print("[\(index + 1)] \(chatRoom.name)")
            }
        }
    }
}
