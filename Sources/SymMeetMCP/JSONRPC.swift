import Foundation

// MARK: - JSON-RPC 2.0 framing types

/// A JSON-RPC 2.0 request object.
struct JSONRPCRequest: Codable, Sendable {
  let jsonrpc: String
  let id: JSONRPCID
  let method: String
  let params: [String: AnyCodable]?

  init(id: JSONRPCID, method: String, params: [String: AnyCodable]? = nil) {
    self.jsonrpc = "2.0"
    self.id = id
    self.method = method
    self.params = params
  }
}

/// A JSON-RPC 2.0 response object.
struct JSONRPCResponse: Codable, Sendable {
  let jsonrpc: String
  let id: JSONRPCID
  let result: AnyCodable?
  let error: JSONRPCError?

  init(id: JSONRPCID, result: AnyCodable) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = result
    self.error = nil
  }

  init(id: JSONRPCID, error: JSONRPCError) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = nil
    self.error = error
  }
}

/// A JSON-RPC 2.0 error object.
struct JSONRPCError: Codable, Sendable {
  let code: Int
  let message: String
  let data: AnyCodable?

  static let parseError = JSONRPCError(code: -32700, message: "Parse error", data: nil)
  static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid request", data: nil)
  static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found", data: nil)
  static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params", data: nil)
  static let internalError = JSONRPCError(code: -32603, message: "Internal error", data: nil)

  static func toolError(_ message: String) -> JSONRPCError {
    JSONRPCError(code: -32000, message: message, data: nil)
  }
}

/// A JSON-RPC 2.0 notification (request with no id).
struct JSONRPCNotification: Codable, Sendable {
  let jsonrpc: String
  let method: String
  let params: [String: AnyCodable]?

  init(method: String, params: [String: AnyCodable]? = nil) {
    self.jsonrpc = "2.0"
    self.method = method
    self.params = params
  }
}

// MARK: - JSON-RPC ID

/// A JSON-RPC 2.0 request identifier: string, number, or null.
enum JSONRPCID: Codable, Sendable, Hashable {
  case string(String)
  case integer(Int)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let integer = try? container.decode(Int.self) {
      self = .integer(integer)
    } else {
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

// MARK: - AnyCodable

/// A type-erased Codable value for dynamic JSON-RPC params.
/// @unchecked Sendable because `Any` is not Sendable by default.
struct AnyCodable: Codable, @unchecked Sendable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues(\.value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Unsupported AnyCodable type")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let int32 as Int32:
      try container.encode(Int(int32))
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodable($0) })
    default:
      try container.encodeNil()
    }
  }

  /// Access the underlying value as a specific type.
  func asType<T>(_ type: T.Type) -> T? { value as? T }

  var asString: String? { value as? String }
  var asInt: Int? { value as? Int }
  var asBool: Bool? { value as? Bool }
  var asDouble: Double? { value as? Double }
  var asDict: [String: Any]? { value as? [String: Any] }
  var asArray: [Any]? { value as? [Any] }

  /// Convenience accessor for a nested dictionary key.
  func asDictValue(_ key: String) -> AnyCodable? {
    guard let dict = value as? [String: Any] else { return nil }
    return dict[key].map { AnyCodable($0) }
  }
}

// MARK: - Stdio transport helpers

/// Reads newline-delimited JSON-RPC messages from stdin.
enum JSONRPCReader {
  /// Reads a single JSON-RPC message from stdin. Returns nil on EOF.
  static func read() -> String? {
    var buffer = ""
    while let line = readLine(strippingNewline: true) {
      buffer += line
      if !buffer.isEmpty && !buffer.hasSuffix("\r") {
        return buffer
      }
    }
    return buffer.isEmpty ? nil : buffer
  }
}

/// Writes a JSON-RPC message to stdout, ensuring only protocol frames are written.
enum JSONRPCWriter {
  /// Writes a JSON-RPC response to stdout.
  static func write(_ response: JSONRPCResponse) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(response)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  }

  /// Writes a JSON-RPC notification to stdout.
  static func write(_ notification: JSONRPCNotification) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(notification)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  }
}

/// Writes diagnostic messages to stderr (never stdout).
enum JSONRPCDiagnostics {
  static func log(_ message: String) {
    FileHandle.standardError.write(Data(("[symmeet-mcp] " + message + "\n").utf8))
  }
}
