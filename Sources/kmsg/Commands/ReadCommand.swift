import ArgumentParser
import Foundation

struct ReadCommand: ParsableCommand {
    private struct ReadMessage: Codable {
        let author: String?
        let timeRaw: String?
        let body: String

        enum CodingKeys: String, CodingKey {
            case author
            case timeRaw = "time_raw"
            case body
        }
    }

    private struct ReadJSONResponse: Codable {
        let chat: String
        let fetchedAt: String
        let count: Int
        let messages: [ReadMessage]

        enum CodingKeys: String, CodingKey {
            case chat
            case fetchedAt = "fetched_at"
            case count
            case messages
        }
    }

    private struct RowMetadata {
        let author: String?
        let timeRaw: String?
    }

    private struct MessageBodyCandidate {
        let body: String
        let frame: CGRect?
    }

    private enum MessageSide: String, Hashable {
        case left
        case right
        case unknown
    }

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

    @Flag(name: [.short, .long], help: "Keep auto-opened chat window after read")
    var keepWindow: Bool = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Enable deep window recovery when fast window detection fails",
            visibility: .default
        )
    )
    var deepRecovery: Bool = false

    @Flag(name: .long, help: "Output in JSON format")
    var json: Bool = false

    func run() throws {
        guard AccessibilityPermission.ensureGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()
        let runner = AXActionRunner(traceEnabled: traceAX)
        let chatWindowResolver = ChatWindowResolver(
            kakao: kakao,
            runner: runner,
            deepRecoveryEnabled: deepRecovery
        )

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
            if keepWindow {
                runner.log("read: keep-window enabled; auto-opened window will be kept")
            } else {
                runner.log("read: auto-opened window will be closed after read")
            }
        } else {
            runner.log("read: found existing chat window")
        }

        defer {
            if resolution.openedViaSearch && !keepWindow {
                let resolvedTitle = window.title ?? ""
                if !resolvedTitle.isEmpty && !resolvedTitle.localizedCaseInsensitiveContains(chat) {
                    runner.log("read: skipped auto-close because resolved title '\(resolvedTitle)' did not match query")
                } else if chatWindowResolver.closeWindow(window) {
                    runner.log("read: auto-opened chat window closed")
                } else {
                    runner.log("read: failed to close auto-opened chat window")
                }
            } else if resolution.openedViaSearch && keepWindow {
                runner.log("read: auto-opened chat window kept by --keep-window")
            }
        }

        let windowTitle = window.title ?? chat
        if !json {
            print("Reading messages from: \(windowTitle)\n")
        }

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

        if json {
            try printMessagesAsJSON(chat: windowTitle, messages: displayMessages)
            return
        }

        print("Recent messages (\(displayMessages.count)):\n")
        for (index, message) in displayMessages.enumerated() {
            if debug {
                print("[\(index + 1)] author=\(message.author ?? "unknown") time=\(message.timeRaw ?? "unknown") body=\(message.body)")
                continue
            }

            print("[\(index + 1)] author: \(message.author ?? "unknown")")
            print("    time: \(message.timeRaw ?? "unknown")")
            print("    body: \(message.body)")
            print("")
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
    ) -> [ReadMessage] {
        var messages: [ReadMessage] = []
        messages.reserveCapacity(min(rows.count, limit * 2))
        var selectedLogs = 0
        var skippedLogs = 0
        var leftAuthor: String?
        var rightAuthor: String?
        var lastKnownTime: String?
        var lastTimeBySide: [MessageSide: String] = [:]

        for (offset, row) in rows.suffix(max(limit * 4, limit)).enumerated() {
            if let bodyCandidate = extractMessageBody(from: row, runner: runner) {
                let metadata = extractRowMetadata(from: row)
                let side = inferMessageSide(
                    bodyFrame: bodyCandidate.frame,
                    row: row,
                    transcriptRoot: transcriptRoot
                )
                let author = resolveAuthor(
                    explicitAuthor: metadata.author,
                    side: side,
                    leftAuthor: &leftAuthor,
                    rightAuthor: &rightAuthor
                )

                let resolvedTime: String?
                if let explicitTime = metadata.timeRaw {
                    resolvedTime = explicitTime
                    lastKnownTime = explicitTime
                    if side != .unknown {
                        lastTimeBySide[side] = explicitTime
                    }
                } else if side != .unknown, let sideTime = lastTimeBySide[side] {
                    resolvedTime = sideTime
                } else {
                    resolvedTime = lastKnownTime
                }

                let message = ReadMessage(
                    author: author,
                    timeRaw: resolvedTime,
                    body: bodyCandidate.body
                )
                messages.append(message)
                if selectedLogs < 10 {
                    runner.log(
                        "read: row[\(offset + 1)] side=\(side.rawValue) author='\(author ?? "unknown")' time='\(resolvedTime ?? "unknown")' body='\(bodyCandidate.body.prefix(60))'"
                    )
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

        return Array(deduplicateMessagesPreservingOrder(messages).suffix(limit))
    }

    private func extractMessageBody(from row: UIElement, runner: AXActionRunner) -> MessageBodyCandidate? {
        let cells = row.findAll(role: kAXCellRole, limit: 8, maxNodes: 180)
        let containers = cells.isEmpty ? [row] : cells

        var candidates: [MessageBodyCandidate] = []
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
                candidates.append(MessageBodyCandidate(body: resolved, frame: textArea.frame))
            }

            if textAreas.isEmpty, let linkOnlyText = bestLinkTitle(from: container) {
                candidates.append(MessageBodyCandidate(body: linkOnlyText, frame: container.frame))
            }
        }

        let uniqueCandidates = deduplicateBodyCandidates(candidates)
        guard !uniqueCandidates.isEmpty else { return nil }

        return uniqueCandidates.max { lhs, rhs in
            scoreBodyCandidate(lhs.body) < scoreBodyCandidate(rhs.body)
        }
    }

    private func extractFallbackMessages(from transcriptRoot: UIElement, limit: Int, runner: AXActionRunner) -> [ReadMessage] {
        var messages: [ReadMessage] = []
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
            let row = firstAncestor(of: textArea, role: kAXRowRole, maxHops: 6)
            let metadata = row.map { extractRowMetadata(from: $0) } ?? RowMetadata(author: nil, timeRaw: nil)
            messages.append(ReadMessage(author: metadata.author, timeRaw: metadata.timeRaw, body: resolved))
        }

        if messages.isEmpty {
            let links = transcriptRoot.findAll(where: { $0.role == kAXLinkRole }, limit: max(limit * 8, 60), maxNodes: 1_200)
            for link in links {
                let title = normalizeBodyText(link.title ?? link.stringValue)
                if !title.isEmpty {
                    messages.append(ReadMessage(author: nil, timeRaw: nil, body: title))
                }
            }
        }

        return Array(deduplicateMessagesPreservingOrder(messages).suffix(limit))
    }

    private func extractRowMetadata(from row: UIElement) -> RowMetadata {
        let cells = row.findAll(role: kAXCellRole, limit: 8, maxNodes: 180)
        let containers = cells.isEmpty ? [row] : cells

        var tokens: [String] = []
        for container in containers {
            let staticTexts = container.findAll(role: kAXStaticTextRole, limit: 12, maxNodes: 240)
            for staticText in staticTexts {
                let normalized = normalizeBodyText(staticText.stringValue)
                guard !normalized.isEmpty else { continue }
                tokens.append(contentsOf: metadataTokens(from: normalized))
            }
        }

        let uniqueTokens = deduplicatePreservingOrder(tokens)
        var author: String?
        var timeRaw: String?

        for token in uniqueTokens {
            if let parsedTime = extractTimeToken(from: token) {
                timeRaw = parsedTime
                continue
            }

            if isLikelyCountToken(token) || isLikelySystemMetadataToken(token) {
                continue
            }

            if author == nil {
                author = token
            }
        }

        return RowMetadata(author: author, timeRaw: timeRaw)
    }

    private func metadataTokens(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractTimeToken(from token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let meridiemRange = trimmed.range(
            of: #"(오전|오후)\s*([1-9]|1[0-2]):[0-5][0-9]"#,
            options: .regularExpression
        ) {
            return String(trimmed[meridiemRange])
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        for part in parts {
            let normalized = String(part).trimmingCharacters(in: .punctuationCharacters)
            if normalized.range(
                of: #"^([01]?[0-9]|2[0-3]):[0-5][0-9]$"#,
                options: .regularExpression
            ) != nil {
                return normalized
            }
        }

        return nil
    }

    private func isLikelyCountToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private func isLikelySystemMetadataToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^\d{4}[./-]\d{1,2}[./-]\d{1,2}"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^\d{1,2}월\s*\d{1,2}일"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func inferMessageSide(bodyFrame: CGRect?, row: UIElement, transcriptRoot: UIElement) -> MessageSide {
        // Primary: AXImage(프로필) 위치 대비 body text 위치로 판단
        if let bodyF = bodyFrame {
            let cell = row.findAll(role: kAXCellRole, limit: 1, maxNodes: 20).first ?? row
            let images = cell.findAll(role: kAXImageRole, limit: 4, maxNodes: 80)
            for image in images {
                guard let imageFrame = image.frame else { continue }
                if imageFrame.midX + 10 < bodyF.minX {
                    return .left
                }
                if imageFrame.midX > bodyF.maxX + 10 {
                    return .right
                }
            }
        }

        // Fallback: midX ratio 방식
        let referenceFrame = bodyFrame ?? row.frame
        guard let candidateFrame = referenceFrame, let transcriptFrame = transcriptRoot.frame else {
            return .unknown
        }

        let ratio = (candidateFrame.midX - transcriptFrame.minX) / max(transcriptFrame.width, 1)
        if ratio <= 0.56 {
            return .left
        }
        if ratio >= 0.62 {
            return .right
        }
        return .unknown
    }

    private func resolveAuthor(
        explicitAuthor: String?,
        side: MessageSide,
        leftAuthor: inout String?,
        rightAuthor: inout String?
    ) -> String? {
        if let explicitAuthor {
            switch side {
            case .left:
                leftAuthor = explicitAuthor
            case .right:
                rightAuthor = explicitAuthor
            case .unknown:
                if leftAuthor == nil {
                    leftAuthor = explicitAuthor
                } else if rightAuthor == nil {
                    rightAuthor = explicitAuthor
                }
            }
            return explicitAuthor
        }

        switch side {
        case .left:
            return leftAuthor
        case .right:
            return rightAuthor
        case .unknown:
            return leftAuthor ?? rightAuthor
        }
    }

    private func firstAncestor(of element: UIElement, role: String, maxHops: Int) -> UIElement? {
        var cursor: UIElement? = element
        var hops = 0

        while let current = cursor, hops <= maxHops {
            if current.role == role {
                return current
            }
            cursor = current.parent
            hops += 1
        }

        return nil
    }

    private func printMessagesAsJSON(chat: String, messages: [ReadMessage]) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let payload = ReadJSONResponse(
            chat: chat,
            fetchedAt: formatter.string(from: Date()),
            count: messages.count,
            messages: messages
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
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

    private func deduplicateBodyCandidates(_ candidates: [MessageBodyCandidate]) -> [MessageBodyCandidate] {
        var seen = Set<String>()
        var unique: [MessageBodyCandidate] = []
        unique.reserveCapacity(candidates.count)

        for candidate in candidates {
            guard !candidate.body.isEmpty else { continue }
            if seen.contains(candidate.body) { continue }
            seen.insert(candidate.body)
            unique.append(candidate)
        }

        return unique
    }

    private func deduplicateMessagesPreservingOrder(_ messages: [ReadMessage]) -> [ReadMessage] {
        var seen = Set<String>()
        var unique: [ReadMessage] = []
        unique.reserveCapacity(messages.count)

        for message in messages {
            let key = "\(message.author ?? "")\u{1F}\(message.timeRaw ?? "")\u{1F}\(message.body)"
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(message)
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
