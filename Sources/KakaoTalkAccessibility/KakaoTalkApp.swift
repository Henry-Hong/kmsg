import ApplicationServices
import AppKit
import Foundation

/// KakaoTalk bundle identifier
public let kakaoTalkBundleIdentifier = "com.kakao.KakaoTalkMac"

/// Represents a chat room item
public struct ChatRoom {
    public let name: String
    public let lastMessage: String?
    public let element: AXUIElement

    public init(name: String, lastMessage: String? = nil, element: AXUIElement) {
        self.name = name
        self.lastMessage = lastMessage
        self.element = element
    }
}

/// Represents a friend item
public struct Friend {
    public let name: String
    public let statusMessage: String?
    public let element: AXUIElement

    public init(name: String, statusMessage: String? = nil, element: AXUIElement) {
        self.name = name
        self.statusMessage = statusMessage
        self.element = element
    }
}

/// Main class for interacting with KakaoTalk via Accessibility APIs
public final class KakaoTalkApp {
    private let appElement: AXUIElement

    /// Initialize with a running KakaoTalk instance
    public init() throws {
        guard AccessibilityHelper.checkAccessibilityStatus() else {
            _ = AccessibilityHelper.isAccessibilityEnabled()
            throw AccessibilityError.accessibilityNotEnabled
        }

        self.appElement = try AccessibilityHelper.getApplicationElement(bundleIdentifier: kakaoTalkBundleIdentifier)
    }

    /// Check if KakaoTalk is currently running
    public static func isRunning() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: kakaoTalkBundleIdentifier).isEmpty
    }

    /// Activate KakaoTalk (bring to front)
    public func activate() throws {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: kakaoTalkBundleIdentifier
        ).first else {
            throw AccessibilityError.kakaoTalkNotRunning
        }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// Get all windows
    public func getWindows() throws -> [AXUIElement] {
        return try AccessibilityHelper.getWindows(for: appElement)
    }

    /// Get the main window
    public func getMainWindow() throws -> AXUIElement? {
        return try AccessibilityHelper.getMainWindow(for: appElement)
    }

    /// Print the UI hierarchy for debugging
    public func printUIHierarchy(maxDepth: Int = 5) throws {
        print("=== KakaoTalk UI Hierarchy ===")
        AccessibilityHelper.printHierarchy(of: appElement, maxDepth: maxDepth)
    }

    /// Get the raw application element for advanced operations
    public var element: AXUIElement {
        return appElement
    }

    /// Get chat rooms from the chat list
    /// KakaoTalk's chat list typically contains rows/cells with chat room info
    public func getChatRooms(limit: Int = 50) throws -> [ChatRoom] {
        guard let mainWindow = try getMainWindow() else {
            throw AccessibilityError.elementNotFound("main window")
        }

        var chatRooms: [ChatRoom] = []

        // Look for table/list elements that contain chat rows
        // KakaoTalk uses various UI patterns - we'll search for common ones
        let rows = findChatListRows(in: mainWindow)

        for row in rows.prefix(limit) {
            if let chatRoom = extractChatRoom(from: row) {
                chatRooms.append(chatRoom)
            }
        }

        return chatRooms
    }

    /// Find chat list rows by searching for common patterns
    private func findChatListRows(in element: AXUIElement) -> [AXUIElement] {
        // Look for AXRow, AXCell, or AXGroup elements that might be chat items
        let possibleRoles = ["AXRow", "AXCell", "AXGroup", "AXButton"]

        var rows: [AXUIElement] = []

        // First, try to find a table/outline/list container
        let containers = AccessibilityHelper.findElements(in: element, matching: { elem in
            let role = AccessibilityHelper.getRole(of: elem)
            return role == "AXTable" || role == "AXOutline" || role == "AXList" || role == "AXScrollArea"
        }, maxDepth: 8)

        // Search within each container for row-like elements
        for container in containers {
            let containerRows = AccessibilityHelper.findElements(in: container, matching: { elem in
                let role = AccessibilityHelper.getRole(of: elem) ?? ""
                return possibleRoles.contains(role)
            }, maxDepth: 5)

            // Filter to only include elements that look like chat items
            // (have text content that could be a chat name)
            for row in containerRows {
                if hasChatRoomContent(row) {
                    rows.append(row)
                }
            }
        }

        return rows
    }

    /// Check if an element has content that looks like a chat room entry
    private func hasChatRoomContent(_ element: AXUIElement) -> Bool {
        // A chat room entry should have at least a title/name
        if let title = AccessibilityHelper.getTitle(of: element), !title.isEmpty {
            return true
        }
        if let value = AccessibilityHelper.getValue(of: element), !value.isEmpty {
            return true
        }

        // Check children for static text elements
        let children = AccessibilityHelper.getChildren(of: element)
        for child in children {
            let role = AccessibilityHelper.getRole(of: child)
            if role == "AXStaticText" {
                if let value = AccessibilityHelper.getValue(of: child), !value.isEmpty {
                    return true
                }
            }
        }

        return false
    }

    /// Extract chat room information from a row element
    private func extractChatRoom(from element: AXUIElement) -> ChatRoom? {
        var name: String?
        var lastMessage: String?

        // Try getting name from title or value
        if let title = AccessibilityHelper.getTitle(of: element), !title.isEmpty {
            name = title
        } else if let value = AccessibilityHelper.getValue(of: element), !value.isEmpty {
            name = value
        }

        // Look through children for text content
        let textElements = AccessibilityHelper.findElements(in: element, matching: { elem in
            AccessibilityHelper.getRole(of: elem) == "AXStaticText"
        }, maxDepth: 3)

        for (index, textElem) in textElements.enumerated() {
            if let text = AccessibilityHelper.getValue(of: textElem), !text.isEmpty {
                if name == nil && index == 0 {
                    name = text
                } else if lastMessage == nil && index > 0 {
                    lastMessage = text
                }
            }
        }

        guard let chatName = name else {
            return nil
        }

        return ChatRoom(name: chatName, lastMessage: lastMessage, element: element)
    }

    /// Open a chat room by clicking on it
    public func openChatRoom(_ chatRoom: ChatRoom) throws {
        try AccessibilityHelper.press(chatRoom.element)
    }

    /// Find a chat room by name (partial match)
    public func findChatRoom(named query: String, limit: Int = 50) throws -> ChatRoom? {
        let chatRooms = try getChatRooms(limit: limit)
        let lowercaseQuery = query.lowercased()
        return chatRooms.first { $0.name.lowercased().contains(lowercaseQuery) }
    }

    /// Find the text input field in a chat window
    public func findTextInputField(in window: AXUIElement? = nil) throws -> AXUIElement? {
        let searchWindow: AXUIElement
        if let window = window {
            searchWindow = window
        } else if let mainWindow = try getMainWindow() {
            searchWindow = mainWindow
        } else {
            throw AccessibilityError.elementNotFound("main window")
        }

        // Look for text area or text field elements that are editable
        let textInputs = AccessibilityHelper.findElements(in: searchWindow, matching: { elem in
            let role = AccessibilityHelper.getRole(of: elem) ?? ""
            return role == "AXTextArea" || role == "AXTextField"
        }, maxDepth: 15)

        // Return the first editable text input found
        for input in textInputs {
            // Check if the element is enabled/editable
            let enabled: Bool? = AccessibilityHelper.getAttribute(kAXEnabledAttribute as String, from: input)
            if enabled == true || enabled == nil {
                return input
            }
        }

        return textInputs.first
    }

    /// Find the send button in a chat window
    public func findSendButton(in window: AXUIElement? = nil) throws -> AXUIElement? {
        let searchWindow: AXUIElement
        if let window = window {
            searchWindow = window
        } else if let mainWindow = try getMainWindow() {
            searchWindow = mainWindow
        } else {
            throw AccessibilityError.elementNotFound("main window")
        }

        // Look for button elements that might be the send button
        let buttons = AccessibilityHelper.findElements(in: searchWindow, matching: { elem in
            AccessibilityHelper.getRole(of: elem) == "AXButton"
        }, maxDepth: 15)

        // Try to find the send button by common identifiers/titles
        let sendKeywords = ["전송", "Send", "send", "보내기"]

        for button in buttons {
            let title = AccessibilityHelper.getTitle(of: button) ?? ""
            let identifier = AccessibilityHelper.getIdentifier(of: button) ?? ""

            for keyword in sendKeywords {
                if title.contains(keyword) || identifier.lowercased().contains(keyword.lowercased()) {
                    return button
                }
            }
        }

        return nil
    }

    /// Send a message to the currently open chat
    public func sendMessage(_ message: String, useSendButton: Bool = false) throws {
        // Find the text input field
        guard let textInput = try findTextInputField() else {
            throw AccessibilityError.elementNotFound("text input field")
        }

        // Set the message text
        try AccessibilityHelper.setValue(message, for: textInput)

        // Small delay to ensure text is set
        Thread.sleep(forTimeInterval: 0.1)

        if useSendButton {
            // Find and click the send button
            guard let sendButton = try findSendButton() else {
                throw AccessibilityError.elementNotFound("send button")
            }
            try AccessibilityHelper.press(sendButton)
        } else {
            // Press Enter to send (simulated by confirming the text field)
            try AccessibilityHelper.performAction(kAXConfirmAction as String, on: textInput)
        }
    }

    /// Send a message to a specific chat room by name
    public func sendMessageTo(chatName: String, message: String) throws {
        // Find and open the chat room
        guard let chatRoom = try findChatRoom(named: chatName) else {
            throw AccessibilityError.elementNotFound("chat room '\(chatName)'")
        }

        // Open the chat room
        try openChatRoom(chatRoom)

        // Wait for the chat window to open
        Thread.sleep(forTimeInterval: 0.3)

        // Send the message
        try sendMessage(message)
    }

    // MARK: - Friends

    /// Get friends from the friend list
    /// KakaoTalk's friend list typically contains rows/cells with friend info
    public func getFriends(limit: Int = 100) throws -> [Friend] {
        guard let mainWindow = try getMainWindow() else {
            throw AccessibilityError.elementNotFound("main window")
        }

        var friends: [Friend] = []

        // Look for table/list elements that contain friend rows
        let rows = findFriendListRows(in: mainWindow)

        for row in rows.prefix(limit) {
            if let friend = extractFriend(from: row) {
                friends.append(friend)
            }
        }

        return friends
    }

    /// Find friend list rows by searching for common patterns
    private func findFriendListRows(in element: AXUIElement) -> [AXUIElement] {
        let possibleRoles = ["AXRow", "AXCell", "AXGroup", "AXButton"]

        var rows: [AXUIElement] = []

        // First, try to find a table/outline/list container
        let containers = AccessibilityHelper.findElements(in: element, matching: { elem in
            let role = AccessibilityHelper.getRole(of: elem)
            return role == "AXTable" || role == "AXOutline" || role == "AXList" || role == "AXScrollArea"
        }, maxDepth: 8)

        // Search within each container for row-like elements
        for container in containers {
            let containerRows = AccessibilityHelper.findElements(in: container, matching: { elem in
                let role = AccessibilityHelper.getRole(of: elem) ?? ""
                return possibleRoles.contains(role)
            }, maxDepth: 5)

            // Filter to only include elements that look like friend items
            for row in containerRows {
                if hasFriendContent(row) {
                    rows.append(row)
                }
            }
        }

        return rows
    }

    /// Check if an element has content that looks like a friend entry
    private func hasFriendContent(_ element: AXUIElement) -> Bool {
        // A friend entry should have at least a name
        if let title = AccessibilityHelper.getTitle(of: element), !title.isEmpty {
            return true
        }
        if let value = AccessibilityHelper.getValue(of: element), !value.isEmpty {
            return true
        }

        // Check children for static text elements
        let children = AccessibilityHelper.getChildren(of: element)
        for child in children {
            let role = AccessibilityHelper.getRole(of: child)
            if role == "AXStaticText" {
                if let value = AccessibilityHelper.getValue(of: child), !value.isEmpty {
                    return true
                }
            }
        }

        return false
    }

    /// Extract friend information from a row element
    private func extractFriend(from element: AXUIElement) -> Friend? {
        var name: String?
        var statusMessage: String?

        // Try getting name from title or value
        if let title = AccessibilityHelper.getTitle(of: element), !title.isEmpty {
            name = title
        } else if let value = AccessibilityHelper.getValue(of: element), !value.isEmpty {
            name = value
        }

        // Look through children for text content
        let textElements = AccessibilityHelper.findElements(in: element, matching: { elem in
            AccessibilityHelper.getRole(of: elem) == "AXStaticText"
        }, maxDepth: 3)

        for (index, textElem) in textElements.enumerated() {
            if let text = AccessibilityHelper.getValue(of: textElem), !text.isEmpty {
                if name == nil && index == 0 {
                    name = text
                } else if statusMessage == nil && index > 0 {
                    statusMessage = text
                }
            }
        }

        guard let friendName = name else {
            return nil
        }

        return Friend(name: friendName, statusMessage: statusMessage, element: element)
    }

    /// Find a friend by name (partial match)
    public func findFriend(named query: String, limit: Int = 100) throws -> Friend? {
        let friends = try getFriends(limit: limit)
        let lowercaseQuery = query.lowercased()
        return friends.first { $0.name.lowercased().contains(lowercaseQuery) }
    }

    /// Open a chat with a friend by clicking on them
    public func openChatWith(_ friend: Friend) throws {
        try AccessibilityHelper.press(friend.element)
    }
}
