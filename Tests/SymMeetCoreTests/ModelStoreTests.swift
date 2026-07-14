import Foundation
import XCTest

@testable import SymMeetCore

final class ModelStoreTests: XCTestCase {
  func testModelsPublishAtomicallyAndCannotBeRemovedWhileInUse() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "download")
    try FileManager.default.createDirectory(
      at: source.appending(path: "payload"), withIntermediateDirectories: true)
    try Data("model".utf8).write(to: source.appending(path: "payload/weights.bin"))

    let store = ModelStore(root: root.appending(path: "models"))
    let available = try await store.list()
    XCTAssertEqual(available.first { $0.descriptor.id == "tiny" }?.status, .available)

    let published = try await store.publish("tiny", from: source, sha256: "abc")
    XCTAssertEqual(published.status, .installed)
    XCTAssertEqual(try await store.verify(id: "tiny").sha256, "abc")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appending(path: "models/tiny/model.json").path))

    try await store.markInUse("tiny")
    do {
      _ = try await store.remove(id: "tiny")
      XCTFail("Expected in-use model removal to fail")
    } catch let error as ModelError {
      XCTAssertEqual(error, .inUse)
    }
    try await store.markAvailable("tiny")
    XCTAssertTrue(try await store.remove(id: "tiny"))
  }

  func testDownloadingAndCorruptStatesAreVisible() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ModelStore(root: root.appending(path: "models"))
    _ = try await store.prepareDownload(for: "tiny")
    XCTAssertEqual(
      try await store.list().first { $0.descriptor.id == "tiny" }?.status, .downloading)

    let corrupt = root.appending(path: "models/large-v3-v20240930_626MB")
    try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
    let record = try await store.list().first { $0.descriptor.id == "large-v3-v20240930_626MB" }
    XCTAssertEqual(record?.status, .corrupt)
  }
}

private func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "symmeet-model-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
