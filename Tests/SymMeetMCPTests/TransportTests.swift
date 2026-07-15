import XCTest

@testable import SymMeetMCP

final class TransportTests: XCTestCase {

  // MARK: - JSON-RPC framing

  func testRequestEncoding() throws {
    let request = JSONRPCRequest(id: .integer(1), method: "initialize")
    let data = try JSONEncoder().encode(request)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(json.contains("\"jsonrpc\":\"2.0\""))
    XCTAssertTrue(json.contains("\"method\":\"initialize\""))
    XCTAssertTrue(json.contains("\"id\":1"))
  }

  func testResponseEncoding() throws {
    let response = JSONRPCResponse(id: .integer(1), result: AnyCodable(["ok": true]))
    let data = try JSONEncoder().encode(response)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(json.contains("\"jsonrpc\":\"2.0\""))
    XCTAssertTrue(json.contains("\"id\":1"))
    XCTAssertNil(response.error)
  }

  func testErrorResponseEncoding() throws {
    let response = JSONRPCResponse(id: .integer(1), error: .methodNotFound)
    let data = try JSONEncoder().encode(response)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(json.contains("-32601"))
    XCTAssertTrue(json.contains("Method not found"))
    XCTAssertNil(response.result)
  }

  func testJSONRPCIDVariants() throws {
    let stringID = JSONRPCID.string("abc-123")
    let intID = JSONRPCID.integer(42)
    let nullID = JSONRPCID.null

    let encoder = JSONEncoder()

    let stringData = try encoder.encode(JSONRPCResponse(id: stringID, result: AnyCodable("ok")))
    XCTAssertTrue(String(decoding: stringData, as: UTF8.self).contains("\"abc-123\""))

    let intData = try encoder.encode(JSONRPCResponse(id: intID, result: AnyCodable("ok")))
    XCTAssertTrue(String(decoding: intData, as: UTF8.self).contains("42"))

    let nullData = try encoder.encode(JSONRPCResponse(id: nullID, result: AnyCodable("ok")))
    XCTAssertTrue(String(decoding: nullData, as: UTF8.self).contains("null"))
  }

  func testNotificationEncoding() throws {
    let notification = JSONRPCNotification(method: "notifications/initialized")
    let data = try JSONEncoder().encode(notification)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(json.contains("\"method\":\"notifications/initialized\""))
    XCTAssertFalse(json.contains("\"id\""))
  }

  // MARK: - JSONRPCError constants

  func testStandardErrors() {
    XCTAssertEqual(JSONRPCError.parseError.code, -32700)
    XCTAssertEqual(JSONRPCError.invalidRequest.code, -32600)
    XCTAssertEqual(JSONRPCError.methodNotFound.code, -32601)
    XCTAssertEqual(JSONRPCError.invalidParams.code, -32602)
    XCTAssertEqual(JSONRPCError.internalError.code, -32603)

    let toolErr = JSONRPCError.toolError("test message")
    XCTAssertEqual(toolErr.code, -32000)
    XCTAssertEqual(toolErr.message, "test message")
  }

  // MARK: - MCPToolResult

  func testToolResultText() {
    let result = MCPToolResult.text("hello world")
    XCTAssertEqual(result.content.count, 1)
    XCTAssertEqual(result.content[0].type, "text")
    XCTAssertEqual(result.content[0].text, "hello world")
    XCTAssertFalse(result.isError)
  }

  func testToolResultError() {
    let result = MCPToolResult.error("something went wrong")
    XCTAssertEqual(result.content.count, 1)
    XCTAssertEqual(result.content[0].type, "text")
    XCTAssertTrue(result.isError)
  }

  // MARK: - Server handles messages

  func testServerInitialize() async {
    let server = MCPServer()
    let request = JSONRPCRequest(id: .integer(1), method: "initialize")
    let response = await server.handleRequest(request)

    XCTAssertNil(response.error)
    XCTAssertNotNil(response.result)
  }

  func testServerToolsList() async {
    let server = MCPServer()
    let request = JSONRPCRequest(id: .integer(2), method: "tools/list")
    let response = await server.handleRequest(request)

    XCTAssertNil(response.error)
    XCTAssertNotNil(response.result)
  }

  func testServerPing() async {
    let server = MCPServer()
    let request = JSONRPCRequest(id: .integer(3), method: "ping")
    let response = await server.handleRequest(request)

    XCTAssertNil(response.error)
    XCTAssertNotNil(response.result)
  }

  func testServerUnknownMethod() async {
    let server = MCPServer()
    let request = JSONRPCRequest(id: .integer(4), method: "unknown/method")
    let response = await server.handleRequest(request)

    XCTAssertNotNil(response.error)
    XCTAssertEqual(response.error?.code, -32601)
  }

  func testServerUnknownTool() async {
    let server = MCPServer()
    let request = JSONRPCRequest(
      id: .integer(5),
      method: "tools/call",
      params: ["name": AnyCodable("nonexistent_tool")]
    )
    let response = await server.handleRequest(request)

    XCTAssertNotNil(response.error)
    XCTAssertTrue(response.error?.message.contains("Unknown tool") ?? false)
  }
}
