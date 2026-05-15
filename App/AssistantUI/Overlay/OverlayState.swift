import Foundation
import SwiftUI
import AssistantShared

@MainActor
final class OverlayState: ObservableObject {

    enum Mode {
        case singleShot
        case chat
        case briefing
    }

    @Published var mode: Mode = .singleShot
    @Published var inputText: String = ""
    @Published var attachedImage: AttachedImage? = nil
    @Published var isSubmitting: Bool = false

    /// Bumped on every summon so the view can re-focus the text field
    /// (`.onAppear` fires only once per view lifecycle, and the panel is reused).
    @Published var focusToken: UUID = UUID()

    /// Conversation thread when in chat mode.
    @Published var messages: [OverlayMessage] = []

    @Published var briefingPayload: BriefingPayload? = nil

    /// Server-allocated conversation ID once chat starts.
    var sessionId: String? = nil

    struct AttachedImage: Equatable {
        let nsImage: NSImage
        let jpegData: Data
        let mediaType: String   // always "image/jpeg" for crops
    }

    struct OverlayMessage: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let text: String
        let modelUsed: String?
        let timestamp: Date

        enum Role { case user, assistant, system }
    }

    /// Reset to single-shot state on dismiss.
    func reset() {
        mode = .singleShot
        inputText = ""
        attachedImage = nil
        isSubmitting = false
        messages = []
        sessionId = nil
        briefingPayload = nil
    }
}
