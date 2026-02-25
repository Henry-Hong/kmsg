import Foundation

@main
struct VersionGenTool {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            throw ToolError.usage
        }

        let versionFilePath = args[1]
        let outputFilePath = args[2]

        let rawVersion = try String(contentsOfFile: versionFilePath, encoding: .utf8)
        guard let firstLine = rawVersion.split(whereSeparator: \.isNewline).first else {
            throw ToolError.invalidVersion("VERSION file is empty")
        }

        let version = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw ToolError.invalidVersion("VERSION file is empty")
        }

        guard isValidSemverLike(version) else {
            throw ToolError.invalidVersion("VERSION must match semver-like format (e.g. 0.1.1)")
        }

        let generated = """
        import Foundation

        enum BuildVersion {
            static let current = "\(escapeForSwiftLiteral(version))"
        }
        """

        let outputURL = URL(fileURLWithPath: outputFilePath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try generated.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func isValidSemverLike(_ version: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z\.-]+)?$"#) else {
            return false
        }
        let range = NSRange(location: 0, length: version.utf16.count)
        return regex.firstMatch(in: version, options: [], range: range) != nil
    }

    private static func escapeForSwiftLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum ToolError: LocalizedError {
    case usage
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: VersionGenTool <VERSION file> <output swift file>"
        case .invalidVersion(let message):
            return message
        }
    }
}
