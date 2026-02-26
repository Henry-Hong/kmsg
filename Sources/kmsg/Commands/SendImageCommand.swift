import ArgumentParser
import AppKit
import Foundation

struct SendImageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send-image",
        abstract: "Send an image to a chat"
    )

    @Argument(help: "Name of the chat or friend to send to")
    var recipient: String

    @Argument(help: "Path to the image file")
    var imagePath: String

    @Flag(name: .long, help: "Show AX traversal and retry details")
    var traceAX: Bool = false

    @Flag(name: .long, help: "Disable AX path cache for this run")
    var noCache: Bool = false

    @Flag(name: [.short, .long], help: "Keep chat window open after sending image")
    var keepWindow: Bool = false

    @Flag(name: .long, help: "Enable deep window recovery when fast window detection fails")
    var deepRecovery: Bool = false

    func run() throws {
        guard AccessibilityPermission.ensureGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let runner = AXActionRunner(traceEnabled: traceAX)
        let imageURL = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            print("Error: File not found at \(imagePath)")
            throw ExitCode.failure
        }

        let kakao = try KakaoTalkApp()
        let chatWindowResolver = ChatWindowResolver(
            kakao: kakao,
            runner: runner,
            useCache: !noCache,
            deepRecoveryEnabled: deepRecovery
        )

        do {
            print("Looking for chat with '\(recipient)'...")
            let resolution = try chatWindowResolver.resolve(query: recipient)
            
            try sendImageToWindow(imageURL, window: resolution.window, kakao: kakao, runner: runner)
            
            if !keepWindow {
                _ = chatWindowResolver.closeWindow(resolution.window)
                print("✓ Chat window closed.")
            }
        } catch {
            print("Failed to send image: \(error)")
            throw ExitCode.failure
        }
    }

    private func sendImageToWindow(_ imageURL: URL, window: UIElement, kakao: KakaoTalkApp, runner: AXActionRunner) throws {
        // 1. Copy image to clipboard
        guard let image = NSImage(contentsOf: imageURL) else {
            throw KakaoTalkError.actionFailed("Failed to load image from \(imageURL.path)")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        runner.log("Image copied to clipboard")

        // 2. Activate KakaoTalk and focus window
        kakao.activate()
        try? window.focus()
        Thread.sleep(forTimeInterval: 0.3)

        // 3. Paste image
        runner.pressPaste()
        runner.log("Paste command sent")

        // 4. Wait for confirmation sheet
        var sheet: UIElement?
        _ = runner.waitUntil(label: "confirmation sheet", timeout: 4.0, pollInterval: 0.2) {
            // Try attribute first
            if let found = window.attributeOptional(kAXSheetsAttribute).flatMap({ (elements: [AXUIElement]) in elements.first }) {
                sheet = UIElement(found)
                return true
            }
            // Fallback: search children for AXSheet role
            if let found = window.findFirst(where: { $0.role == kAXSheetRole }) {
                sheet = found
                return true
            }
            return false
        }

        guard let confirmationSheet = sheet else {
            throw KakaoTalkError.actionFailed("Confirmation sheet did not appear")
        }

        runner.log("Confirmation sheet found")
        Thread.sleep(forTimeInterval: 0.5) // Let sheet settle

        // 5. Click "Send" button on the sheet
        // KakaoTalk's send button title is "전송" or "Send" depending on locale
        let sendButton = confirmationSheet.findAll(role: kAXButtonRole).first { button in
            let title = (button.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title == "전송" || title == "Send"
        }

        guard let button = sendButton else {
            throw KakaoTalkError.elementNotFound("Send button not found on confirmation sheet")
        }

        if !runner.clickWithRetry(button, label: "send button") {
            throw KakaoTalkError.actionFailed("Failed to click send button after retries")
        }
        
        print("✓ Image sent to '\(recipient)'")
        
        // Give it a moment to finish sending
        Thread.sleep(forTimeInterval: 0.5)
    }
}
