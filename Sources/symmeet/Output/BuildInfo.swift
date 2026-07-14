import Foundation

enum BuildInfo {
  /// Release packaging can inject this value without changing CLI contracts.
  static let version = ProcessInfo.processInfo.environment["SYMMEET_VERSION"] ?? "0.1.0-dev"
}
