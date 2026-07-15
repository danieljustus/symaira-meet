import SwiftUI
import SymairaTheme
import SymMeetCore

struct RecordingMenu: View {
  @ObservedObject var model: AgentModel
  @State private var purposeInput: String = ""

  var body: some View {
    VStack(spacing: 16) {
      switch model.state {
      case .idle:
        VStack(spacing: 12) {
          Text("Symaira Meet")
            .font(.headline)
            .foregroundColor(.primary)

          TextField("Purpose of recording...", text: $purposeInput)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 8)

          Button(action: {
            let purpose = purposeInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !purpose.isEmpty else { return }
            model.initiateRecording(purpose: purpose)
          }) {
            Text("Record Meeting")
              .bold()
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .background(purposeInput.isEmpty ? Color.gray : Color.red)
              .foregroundColor(.white)
              .cornerRadius(8)
          }
          .buttonStyle(.plain)
          .disabled(purposeInput.isEmpty)
        }

      case .permissionRequired:
        PermissionView(model: model)

      case .consentConfirmation:
        VStack(spacing: 12) {
          Text("Confirm Consent")
            .font(.headline)
          Text("By proceeding, you authorize this recording. It will process audio locally on your device.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

          HStack {
            Button("Cancel") {
              model.cancelConsent()
            }
            Spacer()
            Button("Confirm") {
              Task {
                await model.confirmConsent(attested: true)
              }
            }
            .buttonStyle(.borderedProminent)
          }
        }

      case .starting:
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Starting capture session...")
            .font(.callout)
        }

      case .recording(let elapsed):
        VStack(spacing: 12) {
          HStack {
            Circle()
              .fill(Color.red)
              .frame(width: 10, height: 10)
            Text("Recording Live")
              .font(.headline)
            Spacer()
            Text(formatTime(elapsed))
              .font(.system(.body, design: .monospaced))
          }

          HStack(spacing: 12) {
            Button(action: {
              Task {
                await model.pause()
              }
            }) {
              Text("Pause")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: {
              Task {
                await model.stop()
              }
            }) {
              Text("Stop")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
          }
        }

      case .paused(let elapsed):
        VStack(spacing: 12) {
          HStack {
            Circle()
              .fill(Color.gray)
              .frame(width: 10, height: 10)
            Text("Paused")
              .font(.headline)
            Spacer()
            Text(formatTime(elapsed))
              .font(.system(.body, design: .monospaced))
          }

          HStack(spacing: 12) {
            Button(action: {
              Task {
                await model.resume()
              }
            }) {
              Text("Resume")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: {
              Task {
                await model.stop()
              }
            }) {
              Text("Stop")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
          }
        }

      case .stopping:
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Finalizing track assets...")
            .font(.callout)
        }

      case .failed(let message):
        VStack(spacing: 12) {
          Text("Recording Failed")
            .font(.headline)
            .foregroundColor(.red)
          Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

          Button("Dismiss") {
            model.resetToIdle()
          }
        }

      case .completed(let meetingID):
        VStack(spacing: 12) {
          Text("Recording Complete")
            .font(.headline)
            .foregroundColor(.green)
          Text("Meeting artifact was successfully stored.")
            .font(.caption)
            .foregroundColor(.secondary)

          HStack(spacing: 8) {
            Button("Reveal in Finder") {
              let layout = ArtifactLayout(dataRoot: SymMeetPaths().dataDirectory)
              let meetingDir = layout.meetingDirectory(meetingID.uuidString.lowercased())
              NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: meetingDir.path)
            }

            Button("Dismiss") {
              model.resetToIdle()
            }
            .buttonStyle(.bordered)
          }
        }
      }

      Divider()

      HStack {
        Button("Quit Agent") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        Spacer()
      }
    }
    .padding()
    .frame(width: 280)
  }

  private func formatTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }
}
