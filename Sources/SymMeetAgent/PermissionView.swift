import SwiftUI
import SymairaTheme

struct PermissionView: View {
  @ObservedObject var model: AgentModel

  var body: some View {
    VStack(spacing: 20) {
      Text("Permissions Required")
        .font(.title2)
        .bold()
        .foregroundColor(.primary)

      Text("Symaira Meet needs microphone and screen recording permissions to capture synchronized system and microphone audio.")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      VStack(spacing: 12) {
        permissionRow(
          name: "Microphone",
          authorized: model.microphoneAuthorized,
          action: {
            Task {
              await model.requestMicrophonePermission()
            }
          }
        )

        permissionRow(
          name: "Screen Recording",
          authorized: model.screenRecordingAuthorized,
          action: {
            Task {
              await model.requestScreenRecordingPermission()
            }
          }
        )
      }
      .padding()
      .background(Color.black.opacity(0.15))
      .cornerRadius(12)

      if !model.microphoneAuthorized || !model.screenRecordingAuthorized {
        Button(action: {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
          }
        }) {
          Text("Open System Settings")
            .font(.callout)
            .underline()
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
    .frame(width: 320)
  }

  private func permissionRow(name: String, authorized: Bool, action: @escaping () -> Void) -> some View {
    HStack {
      Text(name)
        .font(.headline)
        .foregroundColor(.primary)

      Spacer()

      if authorized {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
      } else {
        Button(action: action) {
          Text("Grant")
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
      }
    }
  }
}
