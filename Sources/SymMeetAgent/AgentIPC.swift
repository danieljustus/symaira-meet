import Foundation

/// Handles runtime IPC discovery and communications with other Symaira clients.
/// Operates on runtime contracts and JSON-based configuration files.
public final class AgentIPC: Sendable {
  public init() {}

  public func notifyActiveSession(meetingID: UUID) {
    // Notify local daemon/listeners of active recording session.
    // In beta, communications are via standardized local files.
  }
}
