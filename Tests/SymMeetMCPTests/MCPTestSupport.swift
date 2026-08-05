import Foundation
import XCTest

@testable import SymMeetMCP

/// Parses the JSON payload carried by a text MCP tool result.
func jsonObject(_ result: MCPToolResult) throws -> [String: Any] {
  let text = try XCTUnwrap(result.content.first?.text)
  let data = try XCTUnwrap(text.data(using: .utf8))
  let object = try JSONSerialization.jsonObject(with: data)
  return try XCTUnwrap(object as? [String: Any])
}

func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "symmeet-mcp-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

/// Asserts that an async throwing expression throws.
/// Note: takes a plain closure (not @autoclosure) so trailing-closure call
/// sites actually execute the body; an @autoclosure would capture the
/// closure literal as a value and never observe the throw.
func assertThrowsAsync<T>(
  _ expression: () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {}
}
