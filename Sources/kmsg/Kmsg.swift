import ArgumentParser
import Foundation
import KakaoTalkAccessibility

@main
struct Kmsg: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kmsg",
        abstract: "A CLI tool to interact with KakaoTalk via Accessibility APIs",
        discussion: """
            kmsg allows you to control KakaoTalk from the command line.

            Before using this tool, make sure:
            1. KakaoTalk is running
            2. Accessibility access is granted to this application
               (System Settings > Privacy & Security > Accessibility)
            """,
        version: "0.1.0",
        subcommands: [
            Status.self,
            Hierarchy.self,
            Chats.self,
            Send.self
        ],
        defaultSubcommand: Status.self
    )
}
