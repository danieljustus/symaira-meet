import SwiftUI
import SymairaTheme

struct ConsentSheet: View {
  @ObservedObject var model: AgentModel
  @State private var purposeInput: String = ""

  init(model: AgentModel) {
    self.model = model
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Start Recording")
        .font(.headline)
        .bold()

      Text("Please specify the purpose of the meeting for interactive authorization record. Processing remains local.")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)

      TextField("Purpose (e.g. Daily Standup)", text: $purposeInput)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)

      HStack(spacing: 16) {
        Button("Cancel") {
          model.cancelConsent()
        }
        .buttonStyle(.bordered)

        Button("Start") {
          let trimmed = purposeInput.trimmingCharacters(in: .whitespacesAndNewlines)
          let purpose = trimmed.isEmpty ? "General Meeting" : trimmed
          Task {
            model.initiateRecording(purpose: purpose)
            await model.confirmConsent(attested: true)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(purposeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(width: 320)
  }
}
