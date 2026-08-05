import Foundation
import XCTest

@testable import SymMeetMCP

final class MCPServerToolsCallTests: XCTestCase {

  func testToolsCallRunsMeetingListThroughServer() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let server = MCPServer(agentBridge: LocalAgentBridge(), dataRoot: root)

    let response = await server.handleRequest(
      JSONRPCRequest(
        id: .integer(1), method: "tools/call",
        params: [
          "name": AnyCodable("meeting_list"),
          "arguments": AnyCodable([String: Any]()),
        ]))

    let result = try XCTUnwrap(response.result?.asDict)
    XCTAssertEqual(result["isError"] as? Bool, false)
    let content = try XCTUnwrap(result["content"] as? [Any])
    let first = try XCTUnwrap(content.first as? [String: String])
    let text = try XCTUnwrap(first["text"])
    XCTAssertTrue(text.contains("\"meetings\""))
    XCTAssertTrue(text.contains("\"diagnostics\""))
  }

  func testToolsCallUnknownToolReturnsToolError() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let server = MCPServer(dataRoot: root)

    let response = await server.handleRequest(
      JSONRPCRequest(
        id: .integer(2), method: "tools/call",
        params: [
          "name": AnyCodable("no_such_tool"),
          "arguments": AnyCodable([String: Any]()),
        ]))

    XCTAssertNil(response.result)
    XCTAssertEqual(response.error?.code, -32000)
    XCTAssertTrue(response.error?.message.contains("Unknown tool: no_such_tool") ?? false)
  }
}
