import SwiftUI

struct VoiceControlSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Listen for Hey Diana",
                isOn: Binding(
                    get: { model.voiceAssistant.isEnabled }, set: { model.setVoiceAssistantEnabled($0) })
            ).toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).disabled(
                model.voiceAssistant.status == .enabling)
            Text(
                "Say ‘Hey Diana’, then ‘Schedule a meeting with my client tomorrow at 5 PM’. Diana reads back the date and time and saves only after you say yes. Say cancel to discard it."
            ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
            Label(
                model.voiceAssistant.statusLabel,
                systemImage: model.voiceAssistant.isEnabled ? "mic.fill" : "mic.slash"
            ).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.muted)
            if let problem = model.voiceAssistant.problem {
                Text(problem).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
            }
            Text(
                model.voiceAssistant.isEnabled && model.voiceAssistant.usesOnDeviceRecognition
                    ? "English recognition runs on this Mac. The microphone stays active for the wake phrase until you turn this off."
                    : "Requires microphone and Apple Speech Recognition access. Apple may process audio online if on-device recognition is unavailable. Audio is not sent to Ollama."
            ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
        }
    }
}
