import ArgumentParser
import Foundation
import SymMeetCore

extension SymMeet {
  struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Inspect local symmeet readiness.")

    @Flag(name: .long, help: "Emit one machine-readable diagnostic document.")
    var json = false

    mutating func run() async throws {
      let report = DoctorReport(paths: SymMeetPaths())
      if json {
        try Output.writeJSON(report)
      } else {
        let artifactStoreStatus = report.checks["artifact_store"]?.status ?? "unknown"
        Output.writeLine("OS: \(report.os)")
        Output.writeLine("Architecture: \(report.architecture)")
        Output.writeLine("Artifact store: \(artifactStoreStatus)")
      }
    }
  }
}

private struct DoctorReport: Encodable {
  let os: String
  let architecture: String
  let paths: DoctorPaths
  let disk: DiskReport
  let checks: [String: DoctorCheck]

  init(paths: SymMeetPaths) {
    os = ProcessInfo.processInfo.operatingSystemVersionString
    architecture = Self.machineArchitecture()
    self.paths = DoctorPaths(paths: paths)
    disk = DiskReport(root: paths.dataDirectory)

    let dataExists = FileManager.default.fileExists(atPath: paths.dataDirectory.path)
    let writable = Self.isWritable(paths.dataDirectory)
    checks = [
      "artifact_store": DoctorCheck(
        status: dataExists ? (writable ? "healthy" : "unwritable") : "not_initialized"),
      "capture": DoctorCheck(status: "not_implemented"),
      "models": DoctorCheck(status: "not_implemented"),
    ]
  }

  private static func isWritable(_ url: URL) -> Bool {
    var candidate = url
    while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
      candidate.deleteLastPathComponent()
    }
    return FileManager.default.isWritableFile(atPath: candidate.path)
  }

  private static func machineArchitecture() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafePointer(to: &system.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }
}

private struct DoctorPaths: Encodable {
  let config: PathStatus
  let cache: PathStatus
  let data: PathStatus

  init(paths: SymMeetPaths) {
    config = PathStatus(url: paths.configFile)
    cache = PathStatus(url: paths.workDirectory.deletingLastPathComponent())
    data = PathStatus(url: paths.dataDirectory)
  }
}

private struct PathStatus: Encodable {
  let path: String
  let exists: Bool
  let writable: Bool

  init(url: URL) {
    path = url.path
    exists = FileManager.default.fileExists(atPath: url.path)
    var candidate = url
    while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
      candidate.deleteLastPathComponent()
    }
    writable = FileManager.default.isWritableFile(atPath: candidate.path)
  }
}

private struct DiskReport: Encodable {
  let availableBytes: Int64?

  init(root: URL) {
    var candidate = root
    while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
      candidate.deleteLastPathComponent()
    }
    let capacity = try? candidate.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ).volumeAvailableCapacityForImportantUsage
    if let capacity {
      // Reporting whole gibibytes makes the diagnostic stable across ordinary
      // command invocations while retaining an actionable free-space signal.
      availableBytes = capacity / (1_024 * 1_024 * 1_024) * (1_024 * 1_024 * 1_024)
    } else {
      availableBytes = nil
    }
  }
}

private struct DoctorCheck: Encodable {
  let status: String
}
