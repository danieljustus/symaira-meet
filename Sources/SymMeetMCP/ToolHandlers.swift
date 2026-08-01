import Foundation
import SymMeetCore

// MARK: - Tool handler protocol

/// A handler for a single MCP tool.
protocol MCPToolHandler: Sendable {
  /// The tool name this handler serves.
  var toolName: String { get }

  /// Executes the tool with the given arguments. Returns the content to send back.
  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult
}

// MARK: - Tool result

/// The result returned by a tool handler, conforming to MCP content format.
struct MCPToolResult: Sendable {
  let content: [MCPContent]
  let isError: Bool

  init(content: [MCPContent], isError: Bool = false) {
    self.content = content
    self.isError = isError
  }

  /// Convenience for a single text result.
  static func text(_ text: String, isError: Bool = false) -> MCPToolResult {
    MCPToolResult(content: [MCPContent(type: "text", text: text)], isError: isError)
  }

  /// Encodes one JSON result using the MCP output encoding contract.
  static func json<T: Encodable>(_ value: T) throws -> MCPToolResult {
    let data = try makeEncoder().encode(value)
    return .text(String(decoding: data, as: UTF8.self))
  }

  /// Convenience for an error result.
  static func error(_ message: String) -> MCPToolResult {
    .text(message, isError: true)
  }
}

/// A single content block in a tool result.
struct MCPContent: Codable, Sendable {
  let type: String
  let text: String?
}

// MARK: - JSON encoding helper

private func makeEncoder() -> JSONEncoder {
  let encoder = JSONEncoder()
  encoder.keyEncodingStrategy = .convertToSnakeCase
  encoder.outputFormatting = [.sortedKeys]
  return encoder
}

// MARK: - Shared helpers

func resolveJob(coordinator: JobCoordinator, identifier: String) async throws
  -> TranscriptionJob
{
  if let meetingID = UUID(uuidString: identifier) {
    do {
      return try await coordinator.load(meetingID: meetingID)
    } catch JobError.notFound {
      // Fall through to scan by job ID.
    }
  }

  let result = try await coordinator.list()
  if let job = result.jobs.first(where: {
    $0.jobID.uuidString.lowercased() == identifier.lowercased()
      || $0.jobID.uuidString == identifier
  }) {
    return job
  }

  throw MCPToolError.notFound("No job found for identifier: \(identifier)")
}

// MARK: - MCP tool errors

enum MCPToolError: Error, LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let message): message
    }
  }
}
