import ArgumentParser
import Foundation
import KakaoTalkAccessibility

struct Friends: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List friends from KakaoTalk"
    )

    @Option(name: .shortAndLong, help: "Maximum number of friends to display")
    var limit: Int = 50

    @Flag(name: .shortAndLong, help: "Show detailed information including status message")
    var verbose: Bool = false

    func run() throws {
        let app = try KakaoTalkApp()

        print("Fetching friends...")
        print()

        let friends = try app.getFriends(limit: limit)

        if friends.isEmpty {
            print("No friends found.")
            print()
            print("Note: Make sure the friend list is visible in KakaoTalk.")
            print("      You may need to click on the friend tab first.")
            return
        }

        print("Found \(friends.count) friend(s):")
        print()

        for (index, friend) in friends.enumerated() {
            if verbose {
                print("[\(index + 1)] \(friend.name)")
                if let statusMessage = friend.statusMessage {
                    print("    Status: \(statusMessage)")
                }
                print()
            } else {
                print("[\(index + 1)] \(friend.name)")
            }
        }
    }
}
