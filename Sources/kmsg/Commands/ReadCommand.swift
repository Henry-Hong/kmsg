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
        let chatWindowResolver = ChatWindowResolver(kakao: kakao, runner: runner)

        let resolution: ChatWindowResolution
        do {
            resolution = try chatWindowResolver.resolve(query: chat)
        } catch {
            print("No chat window found for '\(chat)'")
            print("Reason: \(error)")
            print("\nAvailable windows:")
            for (index, window) in kakao.windows.enumerated() {
                print("  [\(index)] \(window.title ?? "(untitled)")")
            }
            throw ExitCode.failure
        }

        let window = resolution.window
        if resolution.openedViaSearch {
            runner.log("read: opening chat via search")
            runner.log("read: auto-opened window will be closed after read")
        } else {
            runner.log("read: found existing chat window")
        }

        defer {
            if resolution.openedViaSearch {
                let resolvedTitle = window.title ?? ""
                if !resolvedTitle.isEmpty && !resolvedTitle.localizedCaseInsensitiveContains(chat) {
                    runner.log("read: skipped auto-close because resolved title '\(resolvedTitle)' did not match query")
                } else if chatWindowResolver.closeWindow(window) {
                    runner.log("read: auto-opened chat window closed")
                } else {
                    runner.log("read: failed to close auto-opened chat window")
                }
            }
        }

        let windowTitle = window.title ?? chat
        print("Reading messages from: \(windowTitle)\n")

        let messageContextResolver = MessageContextResolver(kakao: kakao, runner: runner)
        guard let messageContext = messageContextResolver.resolve(in: window) else {
            print("Could not locate chat transcript area.")
            print("Use 'kmsg inspect --window <n>' to inspect the opened chat window.")
            return
        }

        let messageRows = collectTranscriptRows(
            from: messageContext.transcriptRoot,
            inputElement: messageContext.inputElement,
            messageLimit: limit,
            runner: runner
        )
        if messageRows.isEmpty {
            print("No message rows found in the chat transcript area.")
            print("Use 'kmsg inspect --window <n>' to inspect transcript structure.")
            return
        }

        let displayMessages = extractMessages(
            from: messageRows,
            transcriptRoot: messageContext.transcriptRoot,
            limit: limit,
            runner: runner
        )

        if displayMessages.isEmpty {
            print("No message body text extracted from transcript container.")
            print("Use 'kmsg inspect --window <n>' to inspect message nodes.")
            return
        }

        print("Recent messages (\(displayMessages.count)):\n")

        for (index, message) in displayMessages.enumerated() {
            if debug {
                print("[\(index + 1)] \(message)")
            } else {
                print(message)
                print("")
            }
        }
    }

    private func collectTranscriptRows(
        from transcriptRoot: UIElement,
        inputElement: UIElement,
        messageLimit: Int,
        runner: AXActionRunner
    ) -> [UIElement] {
        let targetRowCount = max(messageLimit * 6, 60)
        var rows = transcriptRoot.findAll(role: kAXRowRole, limit: targetRowCount, maxNodes: 1_200)

        if rows.isEmpty {
            let tables = transcriptRoot.findAll(role: kAXTableRole, limit: 4, maxNodes: 300)
            let outlines = transcriptRoot.findAll(role: kAXOutlineRole, limit: 4, maxNodes: 300)
            let lists = transcriptRoot.findAll(role: kAXListRole, limit: 4, maxNodes: 300)

            for table in tables {
                let remaining = targetRowCount - rows.count
                if remaining <= 0 { break }
                rows.append(contentsOf: table.findAll(role: kAXRowRole, limit: remaining, maxNodes: 320))
            }
            for outline in outlines {
                let remaining = targetRowCount - rows.count
                if remaining <= 0 { break }
                rows.append(contentsOf: outline.findAll(role: kAXRowRole, limit: remaining, maxNodes: 320))
            }
            for list in lists {
                let remaining = targetRowCount - rows.count
                if remaining <= 0 { break }
                rows.append(contentsOf: list.findAll(role: kAXRowRole, limit: remaining, maxNodes: 320))
            }
        }

        if rows.isEmpty {
            let cells = transcriptRoot.findAll(role: kAXCellRole, limit: max(targetRowCount * 2, 120), maxNodes: 1_000)
            rows.append(contentsOf: cells.compactMap(\.parent))
        }

        let deduplicated = deduplicateElements(rows)
        var filtered = deduplicated
        if let inputFrame = inputElement.frame {
            filtered = deduplicated.filter { row in
                guard let rowFrame = row.frame else { return true }
                return rowFrame.maxY <= inputFrame.minY + 20
            }
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsY = lhs.frame?.minY ?? .greatestFiniteMagnitude
            let rhsY = rhs.frame?.minY ?? .greatestFiniteMagnitude
            if lhsY == rhsY {
                let lhsX = lhs.frame?.minX ?? .greatestFiniteMagnitude
                let rhsX = rhs.frame?.minX ?? .greatestFiniteMagnitude
                return lhsX < rhsX
            }
            return lhsY < rhsY
        }

        runner.log("read: transcript rows raw=\(rows.count), unique=\(deduplicated.count), filtered=\(sorted.count)")
        return sorted
    }

    private func extractMessages(
        from rows: [UIElement],
        transcriptRoot: UIElement,
        limit: Int,
        runner: AXActionRunner
    ) -> [String] {
        var messages: [String] = []
        messages.reserveCapacity(min(rows.count, limit * 2))
        var selectedLogs = 0
        var skippedLogs = 0

        for (offset, row) in rows.suffix(max(limit * 4, limit)).enumerated() {
            if let body = extractMessageBody(from: row, runner: runner) {
                messages.append(body)
                if selectedLogs < 10 {
                    runner.log("read: row[\(offset + 1)] message from AXTextArea '\(body.prefix(60))'")
                    selectedLogs += 1
                }
            } else if skippedLogs < 10 {
                runner.log("read: row[\(offset + 1)] skipped (no body text)")
                skippedLogs += 1
            }
        }

        runner.log("read: row parser messages=\(messages.count)")

        if messages.isEmpty || messages.count < max(3, min(limit / 2, 8)) {
            let fallback = extractFallbackMessages(from: transcriptRoot, limit: limit, runner: runner)
            runner.log("read: fallback messages=\(fallback.count)")
            messages.append(contentsOf: fallback)
        }

        return Array(messages.suffix(limit))
    }

    private func extractMessageBody(from row: UIElement, runner: AXActionRunner) -> String? {
        let cells = row.findAll(role: kAXCellRole, limit: 8, maxNodes: 180)
        let containers = cells.isEmpty ? [row] : cells

        var candidates: [String] = []
        for container in containers {
            let textAreas = container.findAll(role: kAXTextAreaRole, limit: 6, maxNodes: 220)
            for textArea in textAreas {
                let normalized = normalizeBodyText(textArea.stringValue)
                guard !normalized.isEmpty else { continue }

                var resolved = normalized
                if shouldPromoteLinkTitle(for: normalized),
                   let fullLink = bestLinkTitle(from: textArea) ?? bestLinkTitle(from: container)
                {
                    if isURLOnlyText(normalized) {
                        resolved = fullLink
                    } else if !normalized.contains(fullLink) {
                        resolved = "\(normalized)\n\(fullLink)"
                    }
                    runner.log("read: link title used as fallback")
                }
                candidates.append(resolved)
            }

            if textAreas.isEmpty, let linkOnlyText = bestLinkTitle(from: container) {
                candidates.append(linkOnlyText)
            }
        }

        let uniqueCandidates = deduplicatePreservingOrder(candidates)
        guard !uniqueCandidates.isEmpty else { return nil }

        return uniqueCandidates.max { lhs, rhs in
            scoreBodyCandidate(lhs) < scoreBodyCandidate(rhs)
        }
    }

    private func extractFallbackMessages(from transcriptRoot: UIElement, limit: Int, runner: AXActionRunner) -> [String] {
        var messages: [String] = []
        let textAreas = transcriptRoot.findAll(role: kAXTextAreaRole, limit: max(limit * 24, 240), maxNodes: 1_800)
        for textArea in textAreas {
            let normalized = normalizeBodyText(textArea.stringValue)
            guard !normalized.isEmpty else { continue }

            var resolved = normalized
            if shouldPromoteLinkTitle(for: normalized), let fullLink = bestLinkTitle(from: textArea) {
                if isURLOnlyText(normalized) {
                    resolved = fullLink
                } else if !normalized.contains(fullLink) {
                    resolved = "\(normalized)\n\(fullLink)"
                }
                runner.log("read: fallback link title used")
            }
            messages.append(resolved)
        }

        if messages.isEmpty {
            let links = transcriptRoot.findAll(where: { $0.role == kAXLinkRole }, limit: max(limit * 8, 60), maxNodes: 1_200)
            for link in links {
                let title = normalizeBodyText(link.title ?? link.stringValue)
                if !title.isEmpty {
                    messages.append(title)
                }
            }
        }

        return Array(deduplicatePreservingOrder(messages).suffix(limit))
    }

    private func bestLinkTitle(from element: UIElement) -> String? {
        let links = element.findAll(where: { $0.role == kAXLinkRole }, limit: 4, maxNodes: 120)
        let titles = links.compactMap { link in
            normalizeBodyText(link.title ?? link.stringValue)
        }
        .filter { !$0.isEmpty }

        return titles.max { lhs, rhs in lhs.count < rhs.count }
    }

    private func normalizeBodyText(_ text: String?) -> String {
        guard let text else { return "" }
        let canonical = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = canonical
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return joined
    }

    private func deduplicatePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        unique.reserveCapacity(values.count)

        for value in values {
            guard !value.isEmpty else { continue }
            if seen.contains(value) { continue }
            seen.insert(value)
            unique.append(value)
        }

        return unique
    }

    private func shouldPromoteLinkTitle(for text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.contains("http://") || lower.contains("https://") else { return false }
        return text.contains("...")
    }

    private func isURLOnlyText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private func scoreBodyCandidate(_ text: String) -> Int {
        var score = min(text.count * 10, 500)
        if text.contains("\n") {
            score += 60
        }
        if text.contains(" ") {
            score += 40
        }
        let lower = text.lowercased()
        if lower.contains("http://") || lower.contains("https://") {
            score += 180
        }
        return score
    }

    private func deduplicateElements(_ elements: [UIElement]) -> [UIElement] {
        var unique: [UIElement] = []
        unique.reserveCapacity(elements.count)
        for element in elements {
            if unique.contains(where: { existing in
                CFEqual(existing.axElement, element.axElement)
            }) {
                continue
            }
            unique.append(element)
        }
        return unique
    }
}
