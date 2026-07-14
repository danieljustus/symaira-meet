import Foundation

public struct ModelDescriptor: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let engineID: String
  public let displayName: String
  public let source: String
  public let license: String
  public let expectedSizeBytes: Int64
  public let upstreamRevision: String
  public let supportedArchitectures: [String]

  public init(
    id: String,
    engineID: String,
    displayName: String,
    source: String,
    license: String,
    expectedSizeBytes: Int64,
    upstreamRevision: String,
    supportedArchitectures: [String]
  ) {
    self.id = id
    self.engineID = engineID
    self.displayName = displayName
    self.source = source
    self.license = license
    self.expectedSizeBytes = expectedSizeBytes
    self.upstreamRevision = upstreamRevision
    self.supportedArchitectures = supportedArchitectures
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case engineID = "engine_id"
    case displayName = "display_name"
    case source
    case license
    case expectedSizeBytes = "expected_size_bytes"
    case upstreamRevision = "upstream_revision"
    case supportedArchitectures = "supported_architectures"
  }
}

public enum ModelStatus: String, Codable, CaseIterable, Sendable {
  case available
  case installed
  case downloading
  case corrupt
  case incompatible
}

public struct ModelRecord: Codable, Equatable, Sendable {
  public let descriptor: ModelDescriptor
  public let status: ModelStatus
  public let installedAt: Date?
  public let sha256: String?

  public init(
    descriptor: ModelDescriptor,
    status: ModelStatus,
    installedAt: Date? = nil,
    sha256: String? = nil
  ) {
    self.descriptor = descriptor
    self.status = status
    self.installedAt = installedAt
    self.sha256 = sha256
  }

  private enum CodingKeys: String, CodingKey {
    case descriptor
    case status
    case installedAt = "installed_at"
    case sha256
  }
}
