import Foundation
import SymMeetCore

// MARK: - MCP Server

/// The MCP server that handles JSON-RPC 2.0 initialize/list/call lifecycle
/// over stdio. Stdout contains only valid JSON-RPC frames; logs and
/// diagnostics go to stderr.
public struct MCPServer: Sendable {
  let agentBridge: AgentBridge

  /// All registered tool handlers, keyed by tool name.
  private let handlers: [String: MCPToolHandler]

  public init(agentBridge: AgentBridge = LocalAgentBridge()) {
    self.agentBridge = agentBridge

    var handlerMap: [String: MCPToolHandler] = [:]
    let allHandlers: [MCPToolHandler] = [
      MeetingListHandler(),
      MeetingGetHandler(),
      MeetingTranscribeHandler(),
      MeetingJobStatusHandler(),
      MeetingJobCancelHandler(),
      MeetingExportHandler(),
      MeetingRecordingStatusHandler(agentBridge: agentBridge),
      MeetingRecordingRequestHandler(agentBridge: agentBridge),
      MeetingRecordingStopHandler(agentBridge: agentBridge),
    ]
    for handler in allHandlers {
      handlerMap[handler.toolName] = handler
    }
    self.handlers = handlerMap
  }

  // MARK: - Message loop

  /// Runs the MCP server, reading JSON-RPC messages from stdin and writing
  /// responses to stdout. Runs until stdin closes (EOF).
  public func run() async {
    JSONRPCDiagnostics.log("symmeet MCP server starting (schema \(SymMeetMCP.protocolSchemaVersion))")

    while let line = readLine(strippingNewline: true) {
      guard !line.isEmpty else { continue }

      guard let data = line.data(using: .utf8) else {
        try? JSONRPCWriter.write(
          JSONRPCResponse(id: .null, error: .parseError))
        continue
      }

      do {
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        let response = await handleRequest(request)
        try JSONRPCWriter.write(response)
      } catch {
        try? JSONRPCWriter.write(
          JSONRPCResponse(id: .null, error: .parseError))
      }
    }

    JSONRPCDiagnostics.log("symmeet MCP server shutting down")
  }

  // MARK: - Request handling

  func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
    switch request.method {
    case "initialize":
      return handleInitialize(request)
    case "notifications/initialized":
      // Notification: no response needed, but we return a response
      // for protocol compatibility.
      return JSONRPCResponse(id: request.id, result: AnyCodable([String: Any]()))
    case "tools/list":
      return handleToolsList(request)
    case "tools/call":
      return await handleToolsCall(request)
    case "ping":
      return JSONRPCResponse(id: request.id, result: AnyCodable([String: Any]()))
    default:
      return JSONRPCResponse(id: request.id, error: .methodNotFound)
    }
  }

  // MARK: - Initialize

  private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
    let result: [String: Any] = [
      "protocolVersion": "2024-11-05",
      "capabilities": [
        "tools": ["listChanged": false]
      ] as [String: Any],
      "serverInfo": [
        "name": "symmeet",
        "version": "0.1.0",
      ],
    ]
    return JSONRPCResponse(id: request.id, result: AnyCodable(result))
  }

  // MARK: - Tools list

  private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
    let tools = MCPToolRegistry.tools
    let result: [String: Any] = ["tools": tools]
    return JSONRPCResponse(id: request.id, result: AnyCodable(result))
  }

  // MARK: - Tools call

  private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
    guard let params = request.params,
      let toolName = params["name"]?.asString
    else {
      return JSONRPCResponse(
        id: request.id,
        error: .invalidParams)
    }

    guard let handler = handlers[toolName] else {
      return JSONRPCResponse(
        id: request.id,
        error: JSONRPCError.toolError("Unknown tool: \(toolName)"))
    }

    let arguments: [String: AnyCodable]
    if let argsValue = params["arguments"] {
      if let dict = argsValue.asDict {
        arguments = dict.mapValues { AnyCodable($0) }
      } else {
        arguments = [:]
      }
    } else {
      arguments = [:]
    }

    do {
      let result = try await handler.execute(args: arguments)
      let resultDict: [String: Any] = [
        "content": result.content.map { ["type": $0.type, "text": $0.text ?? ""] },
        "isError": result.isError,
      ]
      return JSONRPCResponse(id: request.id, result: AnyCodable(resultDict))
    } catch {
      return JSONRPCResponse(
        id: request.id,
        error: JSONRPCError.toolError(error.localizedDescription))
    }
  }
}
