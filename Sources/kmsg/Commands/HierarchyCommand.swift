import ArgumentParser
import Foundation
import KakaoTalkAccessibility

struct Hierarchy: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print KakaoTalk's UI hierarchy for debugging"
    )

    @Option(name: .shortAndLong, help: "Maximum depth to traverse")
    var depth: Int = 5

    func run() throws {
        let app = try KakaoTalkApp()
        try app.printUIHierarchy(maxDepth: depth)
    }
}
