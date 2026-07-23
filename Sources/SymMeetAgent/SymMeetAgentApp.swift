import SwiftUI
import SymMeetCore
import SymairaUpdateCheck

class AppDelegate: NSObject, NSApplicationDelegate {
  var model: AgentModel?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model = model else { return .terminateNow }

    switch model.state {
    case .recording, .paused:
      return confirmTermination()
    default:
      return .terminateNow
    }
  }

  private func confirmTermination() -> NSApplication.TerminateReply {
    let alert = NSAlert()
    alert.messageText = "Quit SymMeetAgent?"
    alert.informativeText = """
      A recording session is currently active. \
      Quitting will stop the session and preserve your recorded track files.
      """
    alert.addButton(withTitle: "Stop and Quit")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      Task { @MainActor in
        if let model = self.model {
          await model.stop()
        }
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    } else {
      return .terminateCancel
    }
  }
}

@main
struct SymMeetAgentApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var model = AgentModel()
  @StateObject private var updateChecker = AgentUpdateChecker.shared

  init() {
    let model = AgentModel()
    _model = StateObject(wrappedValue: model)
    _appDelegate = NSApplicationDelegateAdaptor(AppDelegate.self)
  }

  var body: some Scene {
    MenuBarExtra {
      RecordingMenu(model: model, updateChecker: updateChecker)
        .onAppear { appDelegate.model = model }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "waveform.circle.fill")
          .foregroundColor(isRecording ? .red : .primary)
        if case .recording(let elapsed) = model.state {
          Text(formatTime(elapsed))
            .font(.system(.body, design: .monospaced))
        }
        if case .available = updateChecker.status {
          Image(systemName: "arrow.up.circle.fill")
            .foregroundColor(.orange)
            .font(.caption)
        }
      }
    }
    .onAppear {
      Task {
        await updateChecker.checkForUpdate()
      }
    }
  }

  private var isRecording: Bool {
    switch model.state {
    case .recording:
      return true
    default:
      return false
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
