import Foundation
import SymairaUpdateCheck

/// The known state of the update check.
public enum AgentUpdateStatus: Equatable, Sendable {
  case unknown
  case upToDate
  case available(ReleaseInfo)
  case skipped(ReleaseInfo)
  case error(String)
}

/// Persists which release versions the user dismissed, so they are not re-prompted for them.
public protocol SkippedVersionStore: Sendable {
  func skippedTag() -> String?
  func setSkippedTag(_ tag: String?)
}

/// UserDefaults-backed skipped-version store.
public struct UserDefaultsSkippedVersionStore: SkippedVersionStore, @unchecked Sendable {
  private static let key = "dev.symaira.symmeet.agent.updateSkippedTag"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func skippedTag() -> String? {
    defaults.string(forKey: Self.key)
  }

  public func setSkippedTag(_ tag: String?) {
    if let tag {
      defaults.set(tag, forKey: Self.key)
    } else {
      defaults.removeObject(forKey: Self.key)
    }
  }
}

/// High-level update checker for the SymMeetAgent.
///
/// - Runs a non-blocking GitHub release check on the app's startup.
/// - Caches results on disk (24h TTL by default) so every launch is cheap.
/// - Never blocks the launch path: errors are silently absorbed and reported
///   as `.unknown` / `.error` without crashing or blocking the main thread.
@MainActor
public final class AgentUpdateChecker {
  public static let shared = AgentUpdateChecker()

  @Published public private(set) var status: AgentUpdateStatus = .unknown

  private let checker: UpdateChecker
  private let store: SkippedVersionStore
  private let currentVersion: () -> String

  public init(
    checker: UpdateChecker = UpdateChecker(owner: "danieljustus", repo: "symaira-meet"),
    store: SkippedVersionStore = UserDefaultsSkippedVersionStore(),
    currentVersion: @escaping () -> String = {
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
  ) {
    self.checker = checker
    self.store = store
    self.currentVersion = currentVersion
  }

  /// Check for a newer release. `force` bypasses both the disk cache and the skip gate.
  public func checkForUpdate(force: Bool = false) async {
    do {
      let version = currentVersion()
      let result = try await checker.check(
        currentVersion: version,
        force: force
      )
      guard let release = result else {
        status = .upToDate
        return
      }
      if !force, store.skippedTag() == release.tagName {
        status = .skipped(release)
      } else {
        status = .available(release)
      }
    } catch {
      status = .error(String(describing: error))
    }
  }

  /// Dismiss a specific release so the user is not re-prompted for it.
  public func skip(_ release: ReleaseInfo) {
    store.setSkippedTag(release.tagName)
    status = .skipped(release)
  }
}
