import SwiftUI
import SymMeetCore
import SymairaTheme
import SymairaUpdateCheck

struct RecordingMenu: View {
  @ObservedObject var model: AgentModel
  @ObservedObject var updateChecker: AgentUpdateChecker

  var body: some View {
    VStack(spacing: 16) {
      // Update notification banner (discreet, non-modal)
      updateSection

      switch model.state {
      case .idle:
        idleSection

      case .permissionRequired:
        PermissionView(model: model)

      case .consentConfirmation:
        VStack(spacing: 12) {
          Text("Confirm Consent")
            .font(.headline)
          Text(
            "By proceeding, you authorize this recording. "
              + "It will process audio locally on your device."
          )
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
        recordingSection(elapsed: elapsed)

      case .paused(let elapsed):
        pausedSection(elapsed: elapsed)

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

      // Version info
      HStack {
        Text("v\(BuildInfo.version)")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Button("Quit Agent") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
      }
    }
    .padding()
    .frame(width: 280)
  }

  // MARK: - Update Section

  @ViewBuilder
  private var updateSection: some View {
    switch updateChecker.status {
    case .available(let release):
      HStack(spacing: 8) {
        Image(systemName: "arrow.up.circle.fill")
          .foregroundColor(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("Update available")
            .font(.caption)
            .fontWeight(.semibold)
          Text(release.tagName)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Spacer()
        Button("Skip") {
          updateChecker.skip(release)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(.secondary)
        Link(destination: URL(string: release.htmlURL)!) {
          Image(systemName: "arrow.up.forward.app")
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
      }
      .padding(8)
      .background(Color.orange.opacity(0.1))
      .cornerRadius(6)

    case .error:
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.triangle")
          .foregroundColor(.secondary)
          .font(.caption)
        Text("Update check failed")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Button("Retry") {
          Task { await updateChecker.checkForUpdate(force: true) }
        }
        .buttonStyle(.plain)
        .font(.caption)
      }
      .padding(8)

    default:
      EmptyView()
    }
  }

  // MARK: - Sections

  private var idleSection: some View {
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
        Task { await model.initiateRecording(purpose: purpose) }
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
  }

  // Shared state for the idle section text field
  @State private var purposeInput: String = ""

  private func recordingSection(elapsed: TimeInterval) -> some View {
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
  }

  private func pausedSection(elapsed: TimeInterval) -> some View {
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
