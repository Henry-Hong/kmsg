import ArgumentParser
import Darwin
import Foundation

struct CacheCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Manage AX path cache",
        subcommands: [
            CacheStatusCommand.self,
            CacheClearCommand.self,
            CacheExportCommand.self,
            CacheImportCommand.self,
        ],
        defaultSubcommand: CacheStatusCommand.self
    )
}

struct CacheStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show AX cache status"
    )

    func run() throws {
        let cache = AXPathCacheStore.shared
        let status = cache.status()

        print("AX Cache")
        print("Path: \(status.fileURL.path)")
        print("Exists: \(status.exists ? "yes" : "no")")

        guard status.exists else { return }

        print("Schema: \(status.schemaVersion.map(String.init) ?? "unknown")")
        print("App fingerprint: \(status.appFingerprint ?? "unknown")")
        print("Entries: \(status.entryCount)")
        if let updatedAt = status.updatedAt {
            print("Updated: \(ISO8601DateFormatter().string(from: updatedAt))")
        }
    }
}

struct CacheClearCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear AX cache"
    )

    func run() throws {
        try AXPathCacheStore.shared.clearAll()
        print("AX cache cleared.")
    }
}

struct CacheExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export AX cache JSON"
    )

    @Argument(help: "Destination path for exported JSON")
    var outputPath: String

    func run() throws {
        let destination = resolvedURL(outputPath)
        try AXPathCacheStore.shared.export(to: destination)
        print("AX cache exported to \(destination.path)")
    }
}

struct CacheImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import AX cache JSON"
    )

    @Argument(help: "Path of JSON cache to import")
    var inputPath: String

    func run() throws {
        let source = resolvedURL(inputPath)
        try AXPathCacheStore.shared.importDocument(from: source)
        print("AX cache imported from \(source.path)")
    }
}

private func resolvedURL(_ path: String) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
    let cwdPath = physicalCurrentDirectoryPath()
    let cwd = URL(fileURLWithPath: cwdPath, isDirectory: true)
    return URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL
}

private func physicalCurrentDirectoryPath() -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.currentDirectoryPath, &buffer) != nil else {
        return FileManager.default.currentDirectoryPath
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}
