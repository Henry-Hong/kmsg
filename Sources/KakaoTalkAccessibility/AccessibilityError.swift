import Foundation

/// Errors that can occur when interacting with KakaoTalk via Accessibility APIs
public enum AccessibilityError: LocalizedError {
    case accessibilityNotEnabled
    case kakaoTalkNotRunning
    case kakaoTalkNotFound
    case elementNotFound(String)
    case actionFailed(String)
    case timeout(String)
    case unexpectedUIStructure(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotEnabled:
            return "Accessibility access is not enabled. Please enable it in System Settings > Privacy & Security > Accessibility."
        case .kakaoTalkNotRunning:
            return "KakaoTalk is not running. Please start KakaoTalk first."
        case .kakaoTalkNotFound:
            return "KakaoTalk application not found."
        case .elementNotFound(let element):
            return "UI element not found: \(element)"
        case .actionFailed(let action):
            return "Action failed: \(action)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .unexpectedUIStructure(let description):
            return "Unexpected UI structure: \(description)"
        }
    }
}
