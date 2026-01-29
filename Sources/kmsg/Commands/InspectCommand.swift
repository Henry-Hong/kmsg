import ArgumentParser
import Foundation

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect KakaoTalk UI hierarchy for debugging"
    )

    @Option(name: .shortAndLong, help: "Maximum depth to traverse")
    var depth: Int = 4

    @Option(name: .shortAndLong, help: "Window index to inspect (default: main window)")
    var window: Int?

    @Flag(name: .long, help: "Show all attributes for each element")
    var showAttributes: Bool = false

    func run() throws {
        guard AccessibilityPermission.isGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()
        let windows = kakao.windows

        guard !windows.isEmpty else {
            print("No KakaoTalk windows found.")
            throw ExitCode.failure
        }

        let targetWindow: UIElement
        if let windowIndex = window {
            guard windowIndex >= 0 && windowIndex < windows.count else {
                print("Invalid window index. Available windows: 0-\(windows.count - 1)")
                throw ExitCode.failure
            }
            targetWindow = windows[windowIndex]
        } else {
            targetWindow = kakao.mainWindow ?? windows[0]
        }

        let windowTitle = targetWindow.title ?? "(untitled)"
        print("Inspecting window: \(windowTitle)\n")

        printElement(targetWindow, depth: 0, maxDepth: depth)
    }

    private func printElement(_ element: UIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else {
            let childCount = element.children.count
            if childCount > 0 {
                let indent = String(repeating: "  ", count: depth)
                print("\(indent)... (\(childCount) more children)")
            }
            return
        }

        let indent = String(repeating: "  ", count: depth)
        var info: [String] = []

        if let role = element.role {
            info.append("role: \(role)")
        }
        if let title = element.title, !title.isEmpty {
            info.append("title: \"\(title.prefix(40))\(title.count > 40 ? "..." : "")\"")
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            info.append("id: \(identifier)")
        }
        if let value = element.stringValue, !value.isEmpty {
            let truncated = value.prefix(30)
            info.append("value: \"\(truncated)\(value.count > 30 ? "..." : "")\"")
        }
        if element.isFocused {
            info.append("focused")
        }

        print("\(indent)[\(info.joined(separator: ", "))]")

        if showAttributes {
            do {
                let attrs = try element.attributeNames()
                let attrIndent = indent + "  "
                for attr in attrs.prefix(20) {
                    if let val: Any = element.attributeOptional(attr) {
                        print("\(attrIndent)\(attr) = \(String(describing: val).prefix(50))")
                    }
                }
            } catch {
                // Ignore attribute errors
            }
        }

        for child in element.children {
            printElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
