import ApplicationServices.HIServices
import Foundation

enum ChatWindowResolutionMethod {
    case existingWindow
    case openedViaSearch
}

struct ChatWindowResolution {
    let window: UIElement
    let method: ChatWindowResolutionMethod

    var openedViaSearch: Bool {
        method == .openedViaSearch
    }
}

private enum ChatWindowFailureCode: String {
    case focusFail = "FOCUS_FAIL"
    case inputNotReflected = "INPUT_NOT_REFLECTED"
    case windowNotReady = "WINDOW_NOT_READY"
    case searchMiss = "SEARCH_MISS"
}

struct ChatWindowResolver {
    private let kakao: KakaoTalkApp
    private let runner: AXActionRunner
    private let useCache: Bool

    init(kakao: KakaoTalkApp, runner: AXActionRunner, useCache: Bool = true) {
        self.kakao = kakao
        self.runner = runner
        self.useCache = useCache
    }

    func resolve(query: String) throws -> ChatWindowResolution {
        let usableWindow = try requireUsableWindow()

        if let existingWindow = findMatchingChatWindow(in: kakao.windows, query: query) {
            return ChatWindowResolution(window: existingWindow, method: .existingWindow)
        }

        let searchWindow = selectSearchWindow(fallback: usableWindow)
        let chatWindow = try openChatViaSearch(query: query, in: searchWindow, fallbackWindow: usableWindow)
        return ChatWindowResolution(window: chatWindow, method: .openedViaSearch)
    }

    @discardableResult
    func closeWindow(_ window: UIElement) -> Bool {
        let closeAction = "AXClose"

        kakao.activate()
        _ = tryRaiseWindow(window)

        if supportsAction(closeAction, on: window) {
            do {
                try window.performAction(closeAction)
                if waitForWindowClosed(window, label: "close via AXClose") {
                    return true
                }
            } catch {
                runner.log("close window: AXClose failed (\(error))")
            }
        }

        if let closeButton = findCloseButton(in: window) {
            do {
                try closeButton.press()
                if waitForWindowClosed(window, label: "close via button") {
                    return true
                }
            } catch {
                runner.log("close window: button press failed (\(error))")
            }
        }

        runner.log("close window: fallback via cmd+w")
        runner.pressCommandW()
        return waitForWindowClosed(window, label: "close via cmd+w")
    }

    private func requireUsableWindow() throws -> UIElement {
        if let usableWindow = kakao.ensureMainWindow(timeout: 1.2, mode: .fast, trace: { message in
            runner.log(message)
        }) {
            return usableWindow
        }

        runner.log("window fast path failed; escalating to recovery mode")
        if let usableWindow = kakao.ensureMainWindow(timeout: 3.0, mode: .recovery, trace: { message in
            runner.log(message)
        }) {
            return usableWindow
        }

        throw KakaoTalkError.actionFailed("[\(ChatWindowFailureCode.windowNotReady.rawValue)] Usable KakaoTalk window unavailable")
    }

    private func selectSearchWindow(fallback: UIElement) -> UIElement {
        if let chatListWindow = kakao.chatListWindow {
            runner.log("search root selected: chatListWindow")
            return chatListWindow
        }
        if let mainWindow = kakao.mainWindow {
            runner.log("search root selected: mainWindow")
            return mainWindow
        }
        runner.log("search root selected: fallback usable window")
        return fallback
    }

    private func openChatViaSearch(query: String, in rootWindow: UIElement, fallbackWindow: UIElement) throws -> UIElement {
        runner.log("search: locating search field")

        guard let searchField = locateSearchField(in: rootWindow) else {
            throw KakaoTalkError.elementNotFound("[\(ChatWindowFailureCode.searchMiss.rawValue)] Search field not found")
        }

        guard runner.focusWithVerification(searchField, label: "search field", attempts: 1) else {
            throw KakaoTalkError.actionFailed("[\(ChatWindowFailureCode.focusFail.rawValue)] Could not focus search field")
        }

        _ = runner.setTextWithVerification("", on: searchField, label: "search field clear", attempts: 1)

        let searchInputReady =
            runner.setTextWithVerification(query, on: searchField, label: "search field input", attempts: 1) ||
            runner.typeTextWithVerification(query, on: searchField, label: "search field input", attempts: 2)

        guard searchInputReady else {
            runner.pressEscape()
            throw KakaoTalkError.actionFailed("[\(ChatWindowFailureCode.inputNotReflected.rawValue)] Search keyword was not entered")
        }

        let matchingCandidates = waitForMatchingSearchResults(query: query, rootWindow: rootWindow)
        guard let matchingResult = pickBestSearchResult(from: matchingCandidates) else {
            runner.pressEscape()
            throw KakaoTalkError.elementNotFound("[\(ChatWindowFailureCode.searchMiss.rawValue)] No search result found for '\(query)'")
        }

        let openTriggered = triggerSearchResultOpen(
            matchingResult,
            searchField: searchField
        ) {
            resolveOpenedChatWindowFast(query: query) != nil
        }
        guard openTriggered else {
            runner.pressEscape()
            throw KakaoTalkError.actionFailed("[\(ChatWindowFailureCode.searchMiss.rawValue)] Could not open matched search result")
        }

        if let window = waitForOpenedChatWindow(query: query, fallbackWindow: fallbackWindow) {
            return window
        }

        throw KakaoTalkError.windowNotFound("[\(ChatWindowFailureCode.windowNotReady.rawValue)] Chat window for '\(query)' did not open")
    }

    private func resolveCachedElement(
        slot: AXPathSlot,
        root: UIElement,
        validate: (UIElement) -> Bool
    ) -> UIElement? {
        guard useCache else { return nil }
        return AXPathCacheStore.shared.resolve(
            slot: slot,
            root: root,
            validate: validate,
            trace: { message in
                runner.log(message)
            }
        )
    }

    private func rememberCachedElement(slot: AXPathSlot, root: UIElement, element: UIElement) {
        guard useCache else { return }
        AXPathCacheStore.shared.remember(
            slot: slot,
            root: root,
            element: element,
            trace: { message in
                runner.log(message)
            }
        )
    }

    private func locateSearchField(in rootWindow: UIElement) -> UIElement? {
        if let cachedSearchField = resolveCachedElement(
            slot: .searchField,
            root: rootWindow,
            validate: { field in
                field.isEnabled && field.role == kAXTextFieldRole
            }
        ) {
            return cachedSearchField
        }

        let initialFields = discoverSearchFieldCandidates(in: rootWindow)
        if let field = pickSearchField(from: initialFields) {
            rememberCachedElement(slot: .searchField, root: rootWindow, element: field)
            return field
        }

        let searchButtons = rootWindow.findAll(role: kAXButtonRole, limit: 24, maxNodes: 220).filter { button in
            let title = (button.title ?? "").lowercased()
            let description = (button.axDescription ?? "").lowercased()
            let identifier = (button.identifier ?? "").lowercased()

            if identifier == "friends" || identifier == "chatrooms" || identifier == "more" {
                return false
            }

            return title.contains("search")
                || title.contains("검색")
                || description.contains("search")
                || description.contains("검색")
                || identifier.contains("search")
        }

        for button in searchButtons.prefix(4) {
            do {
                try button.press()
                runner.log("search: pressed search-like button title='\(button.title ?? "")' id='\(button.identifier ?? "")'")
            } catch {
                runner.log("search: search-like button press failed (\(error))")
            }

            Thread.sleep(forTimeInterval: 0.08)
            let fields = discoverSearchFieldCandidates(in: rootWindow)
            if let field = pickSearchField(from: fields) {
                rememberCachedElement(slot: .searchField, root: rootWindow, element: field)
                return field
            }
        }

        return nil
    }

    private func discoverSearchFieldCandidates(in rootWindow: UIElement) -> [UIElement] {
        var fields: [UIElement] = []
        fields.append(contentsOf: rootWindow.findAll(role: kAXTextFieldRole, limit: 8, maxNodes: 140))
        if let focusedWindow = kakao.focusedWindow {
            fields.append(contentsOf: focusedWindow.findAll(role: kAXTextFieldRole, limit: 8, maxNodes: 140))
        }
        if let mainWindow = kakao.mainWindow {
            fields.append(contentsOf: mainWindow.findAll(role: kAXTextFieldRole, limit: 8, maxNodes: 140))
        }
        return fields.filter { $0.isEnabled }
    }

    private func waitForMatchingSearchResults(query: String, rootWindow: UIElement) -> [UIElement] {
        var matches: [UIElement] = []
        let found = runner.waitUntil(label: "search results", timeout: 0.4, pollInterval: 0.05) {
            matches = findMatchingSearchResults(query: query, rootWindow: rootWindow)
            return !matches.isEmpty
        }

        if !found {
            matches = findMatchingSearchResults(query: query, rootWindow: rootWindow)
        }
        runner.log("search: matching candidates=\(matches.count)")
        return matches
    }

    private func findMatchingSearchResults(query: String, rootWindow: UIElement) -> [UIElement] {
        var roots: [UIElement] = [rootWindow]
        if let focusedWindow = kakao.focusedWindow {
            roots.append(focusedWindow)
        }
        if let mainWindow = kakao.mainWindow {
            roots.append(mainWindow)
        }

        var results: [UIElement] = []
        for root in roots {
            let candidates = (root.findAll(role: kAXRowRole, limit: 24, maxNodes: 260) + root.findAll(role: kAXCellRole, limit: 24, maxNodes: 260)).filter { element in
                containsText(query, in: element)
            }
            results.append(contentsOf: candidates)
            if !candidates.isEmpty {
                break
            }
        }
        return results
    }

    private func waitForOpenedChatWindow(query: String, fallbackWindow: UIElement) -> UIElement? {
        var resolved: UIElement?
        _ = runner.waitUntil(label: "chat context ready", timeout: 0.8, pollInterval: 0.05, evaluateAfterTimeout: false) {
            resolved = resolveOpenedChatWindowFast(query: query)
            return resolved != nil
        }
        return resolved ?? resolveOpenedChatWindow(query: query, fallbackWindow: fallbackWindow)
    }

    private func resolveOpenedChatWindowFast(query: String) -> UIElement? {
        if let matchedWindow = findMatchingChatWindow(in: kakao.windows, query: query) {
            return matchedWindow
        }

        if let focusedWindow = kakao.focusedWindow,
           let title = focusedWindow.title,
           title.localizedCaseInsensitiveContains(query)
        {
            return focusedWindow
        }

        return nil
    }

    private func resolveOpenedChatWindow(query: String, fallbackWindow: UIElement) -> UIElement? {
        if let fastWindow = resolveOpenedChatWindowFast(query: query) {
            return fastWindow
        }

        if let matchedWindow = findMatchingChatWindow(in: kakao.windows, query: query) {
            return matchedWindow
        }

        if let focusedWindow = kakao.focusedWindow, windowContainsLikelyChatInput(focusedWindow) {
            return focusedWindow
        }

        if windowContainsLikelyChatInput(fallbackWindow) {
            return fallbackWindow
        }

        if let mainWindow = kakao.mainWindow, windowContainsLikelyChatInput(mainWindow) {
            return mainWindow
        }

        return nil
    }

    private func windowContainsLikelyChatInput(_ window: UIElement) -> Bool {
        if window.findFirst(where: { element in
            guard element.isEnabled else { return false }
            return element.role == kAXTextAreaRole
        }) != nil {
            return true
        }

        return window.findFirst(where: { element in
            isLikelyMessageInputElement(element, in: window) && element.role != kAXTextFieldRole
        }) != nil
    }

    private func isLikelyMessageInputElement(_ element: UIElement, in window: UIElement? = nil) -> Bool {
        guard element.isEnabled else { return false }
        let role = element.role ?? ""
        if role == kAXTextAreaRole {
            return true
        }

        let editable: Bool = element.attributeOptional(kAXEditableAttribute) ?? false
        guard editable else { return false }
        guard role != kAXStaticTextRole && role != kAXImageRole else { return false }
        if role == kAXTextFieldRole, isLikelySearchField(element, in: window) {
            return false
        }
        return true
    }

    private func isLikelySearchField(_ element: UIElement, in window: UIElement?) -> Bool {
        let role = element.role ?? ""
        guard role == kAXTextFieldRole else { return false }

        let joinedText = [
            element.identifier ?? "",
            element.title ?? "",
            element.axDescription ?? "",
        ]
        .joined(separator: " ")
        .lowercased()

        if joinedText.contains("search") || joinedText.contains("검색") {
            return true
        }

        guard let windowFrame = window?.frame, let elementFrame = element.frame, windowFrame.height > 0 else {
            return false
        }

        if !isElementLikelyInsideWindow(elementFrame: elementFrame, windowFrame: windowFrame) {
            return true
        }

        let relativeY = (elementFrame.midY - windowFrame.minY) / windowFrame.height
        return relativeY < 0.5
    }

    private func pickBestSearchResult(from candidates: [UIElement]) -> UIElement? {
        guard !candidates.isEmpty else { return nil }
        let best = candidates.max { lhs, rhs in
            scoreSearchResult(lhs) < scoreSearchResult(rhs)
        }
        if let best {
            runner.log("search: best result role='\(best.role ?? "unknown")' title='\(best.title ?? "")'")
        }
        return best
    }

    private func scoreSearchResult(_ element: UIElement) -> Int {
        var score = 0
        if supportsAction("AXPress", on: element) {
            score += 10_000
        }
        if supportsAction("AXConfirm", on: element) {
            score += 8_000
        }
        if element.role == kAXRowRole {
            score += 4_000
        } else if element.role == kAXCellRole {
            score += 3_000
        }
        if let title = element.title, !title.isEmpty {
            score += 500
        }
        if element.role == nil || element.role?.isEmpty == true {
            score -= 2_000
        }
        return score
    }

    private func triggerSearchResultOpen(
        _ result: UIElement,
        searchField: UIElement,
        opened: () -> Bool
    ) -> Bool {
        var didTriggerAction = false

        if tryActivateSearchResult(result, label: "result") {
            didTriggerAction = true
            if runner.waitUntil(label: "search open confirm", timeout: 0.3, pollInterval: 0.05, evaluateAfterTimeout: false, condition: opened) {
                return true
            }
        }
        runner.log("search: direct activate miss; skipping heavy neighbor scan for speed")

        let selected = trySelectSearchResult(result, label: "result")
        if !selected, let parent = result.parent {
            let parentSelected = trySelectSearchResult(parent, label: "result.parent")
            didTriggerAction = didTriggerAction || parentSelected
        }
        didTriggerAction = didTriggerAction || selected
        if selected,
           runner.waitUntil(label: "search open confirm", timeout: 0.18, pollInterval: 0.05, evaluateAfterTimeout: false, condition: opened)
        {
            return true
        }

        kakao.activate()
        if runner.focusWithVerification(searchField, label: "search field confirm", attempts: 1) {
            runner.log("search: fallback confirm via Enter")
            runner.pressEnterKey()
            didTriggerAction = true
            if runner.waitUntil(label: "search open confirm", timeout: 0.28, pollInterval: 0.05, evaluateAfterTimeout: false, condition: opened) {
                return true
            }
        } else {
            runner.log("search: fallback confirm skipped (search field focus failed)")
        }

        kakao.activate()
        if searchField.isFocused || runner.focusWithVerification(searchField, label: "search field confirm", attempts: 1) {
            runner.log("search: fallback confirm via Down+Enter")
            runner.pressDownArrowKey()
            Thread.sleep(forTimeInterval: 0.03)
            runner.pressEnterKey()
            didTriggerAction = true
            if runner.waitUntil(label: "search open confirm", timeout: 0.32, pollInterval: 0.05, evaluateAfterTimeout: false, condition: opened) {
                return true
            }
        } else {
            runner.log("search: Down+Enter skipped (search field focus unavailable)")
        }

        return didTriggerAction
    }

    private func tryActivateSearchResult(_ element: UIElement, label: String) -> Bool {
        if let actions = try? element.actionNames(), !actions.isEmpty {
            runner.log("search: \(label) actions=\(actions.joined(separator: ","))")
        }

        do {
            if supportsAction("AXPress", on: element) {
                try element.press()
                runner.log("search: \(label) activated via AXPress")
                return true
            }
        } catch {
            runner.log("search: \(label) AXPress failed (\(error))")
        }

        do {
            if supportsAction("AXConfirm", on: element) {
                try element.performAction("AXConfirm")
                runner.log("search: \(label) activated via AXConfirm")
                return true
            }
        } catch {
            runner.log("search: \(label) AXConfirm failed (\(error))")
        }

        return false
    }

    private func trySelectSearchResult(_ element: UIElement, label: String) -> Bool {
        do {
            try element.setAttribute("AXSelected", value: true as CFBoolean)
            runner.log("search: \(label) selected via AXSelected=true")
            return true
        } catch {
            runner.log("search: \(label) select failed (\(error))")
            return false
        }
    }

    private func supportsAction(_ action: String, on element: UIElement) -> Bool {
        guard let actions = try? element.actionNames() else { return false }
        return actions.contains(action)
    }

    private func findMatchingChatWindow(in windows: [UIElement], query: String) -> UIElement? {
        windows.first { window in
            guard let title = window.title else { return false }
            return title.localizedCaseInsensitiveContains(query)
        }
    }

    private func pickSearchField(from fields: [UIElement]) -> UIElement? {
        fields
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                let lhsY = lhs.position?.y ?? .greatestFiniteMagnitude
                let rhsY = rhs.position?.y ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
            .first
    }

    private func containsText(_ text: String, in element: UIElement) -> Bool {
        if let title = element.title, title.localizedCaseInsensitiveContains(text) {
            return true
        }
        if let value = element.stringValue, value.localizedCaseInsensitiveContains(text) {
            return true
        }
        let staticTexts = element.findAll(role: kAXStaticTextRole, limit: 5, maxNodes: 48)
        return staticTexts.contains { item in
            (item.stringValue ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    private func tryRaiseWindow(_ window: UIElement) -> Bool {
        if supportsAction(kAXRaiseAction, on: window) {
            do {
                try window.performAction(kAXRaiseAction)
                runner.log("window: raised via AXRaise")
                return true
            } catch {
                runner.log("window: AXRaise failed (\(error))")
            }
        }
        return false
    }

    private func findCloseButton(in window: UIElement) -> UIElement? {
        let buttons = window.findAll(role: kAXButtonRole, limit: 6, maxNodes: 80)
        if let match = buttons.first(where: { button in
            let joined = [
                button.identifier ?? "",
                button.title ?? "",
                button.axDescription ?? "",
            ].joined(separator: " ").lowercased()
            return joined.contains("close") || joined.contains("닫기")
        }) {
            return match
        }

        return buttons.first
    }

    private func waitForWindowClosed(_ window: UIElement, label: String) -> Bool {
        runner.waitUntil(label: label, timeout: 0.9, pollInterval: 0.06, evaluateAfterTimeout: false) {
            !kakao.windows.contains { candidate in
                areSameAXElement(candidate, window)
            }
        }
    }

    private func areSameAXElement(_ lhs: UIElement, _ rhs: UIElement) -> Bool {
        CFEqual(lhs.axElement, rhs.axElement)
    }

    private func isElementLikelyInsideWindow(elementFrame: CGRect, windowFrame: CGRect) -> Bool {
        let expandedWindow = windowFrame.insetBy(dx: -24, dy: -24)
        return expandedWindow.intersects(elementFrame)
    }
}
