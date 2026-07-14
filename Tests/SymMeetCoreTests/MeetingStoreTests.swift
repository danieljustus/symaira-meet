import Foundation
import XCTest

@testable import SymMeetCore

final class MeetingStoreTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appending(
      path: "symmeet-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testCreatesLoadsAndUsesPortableLayout() async throws {
    let store = MeetingStore(dataRoot: root)
    let manifest = makeManifest()

    try await store.create(manifest)
    let loaded = try await store.load(meetingID: manifest.meetingID.uuidString)
    let directory = root.appending(path: "meetings/\(manifest.meetingID.uuidString.lowercased())")

    XCTAssertEqual(loaded.meetingID, manifest.meetingID)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appending(path: "manifest.json").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appending(path: "events.jsonl").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appending(path: "segments.raw.jsonl").path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "segments.edited.jsonl").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: directory.appending(path: "transcript.md").path))
  }

  func testRejectsDuplicateMeetingID() async throws {
    let store = MeetingStore(dataRoot: root)
    let manifest = makeManifest()
    try await store.create(manifest)

    await assertThrowsErrorAsync(try await store.create(manifest)) { error in
      XCTAssertEqual(error as? StoreError, .alreadyExists)
    }
  }

  func testInterruptedTemporaryWriteLeavesExistingManifestReadable() async throws {
    let store = MeetingStore(dataRoot: root)
    let manifest = makeManifest()
    try await store.create(manifest)

    let directory = root.appending(path: "meetings/\(manifest.meetingID.uuidString.lowercased())")
    let interrupted = directory.appending(path: ".manifest.json.interrupted.tmp")
    try Data("not valid JSON".utf8).write(to: interrupted)

    let loaded = try await store.load(meetingID: manifest.meetingID.uuidString)
    XCTAssertEqual(loaded.meetingID, manifest.meetingID)
  }

  func testListReportsMalformedArtifactsWithoutDroppingValidMeetings() async throws {
    let store = MeetingStore(dataRoot: root)
    let manifest = makeManifest()
    try await store.create(manifest)
    let malformed = root.appending(path: "meetings/not-a-uuid")
    try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
    let malformedID = UUID().uuidString.lowercased()
    let malformedManifest = root.appending(path: "meetings/\(malformedID)")
    try FileManager.default.createDirectory(
      at: malformedManifest, withIntermediateDirectories: true)
    try Data("not JSON".utf8).write(to: malformedManifest.appending(path: "manifest.json"))

    let result = try await store.list()

    XCTAssertEqual(result.meetings.map(\.meetingID), [manifest.meetingID])
    XCTAssertTrue(
      result.diagnostics.contains(StoreDiagnostic(meetingID: malformedID, code: .malformedManifest))
    )
    XCTAssertTrue(
      result.diagnostics.contains(
        StoreDiagnostic(meetingID: "not-a-uuid", code: .invalidMeetingDirectory)))
  }

  func testRejectsArtifactPathTraversalBeforeWriting() async throws {
    let store = MeetingStore(dataRoot: root)
    let initial = makeManifest()
    let manifest = MeetingManifest(
      meetingID: initial.meetingID,
      source: initial.source,
      createdAt: initial.createdAt,
      updatedAt: initial.updatedAt,
      originalAsset: "../outside.m4a",
      consent: initial.consent,
      retention: initial.retention
    )

    await assertThrowsErrorAsync(try await store.create(manifest)) { error in
      XCTAssertEqual(error as? StoreError, .invalidRelativePath)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "outside.m4a").path))
  }

  func testRejectsTraversalAndSymlinkEscapes() async throws {
    let store = MeetingStore(dataRoot: root)
    let outside = FileManager.default.temporaryDirectory.appending(
      path: "outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }

    await assertThrowsErrorAsync(try await store.load(meetingID: "../outside")) { error in
      XCTAssertEqual(error as? StoreError, .invalidMeetingID)
    }

    let meetingID = UUID().uuidString.lowercased()
    let meetings = root.appending(path: "meetings")
    try FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: meetings.appending(path: meetingID), withDestinationURL: outside)

    await assertThrowsErrorAsync(try await store.load(meetingID: meetingID)) { error in
      XCTAssertEqual(error as? StoreError, .unsafePath)
    }
  }

  func testTrashRestoreAndPermanentDeleteAreSafeAndIdempotent() async throws {
    let store = MeetingStore(dataRoot: root)
    let manifest = makeManifest()
    try await store.create(manifest)

    try await store.trash(meetingID: manifest.meetingID.uuidString)
    await assertThrowsErrorAsync(try await store.load(meetingID: manifest.meetingID.uuidString)) {
      error in
      XCTAssertEqual(error as? StoreError, .missing)
    }

    try await store.restore(meetingID: manifest.meetingID.uuidString)
    let restored = try await store.load(meetingID: manifest.meetingID.uuidString)
    XCTAssertEqual(restored.meetingID, manifest.meetingID)

    try await store.trash(meetingID: manifest.meetingID.uuidString)
    let didDelete = try await store.permanentlyDelete(meetingID: manifest.meetingID.uuidString)
    let didDeleteAgain = try await store.permanentlyDelete(meetingID: manifest.meetingID.uuidString)
    XCTAssertTrue(didDelete)
    XCTAssertFalse(didDeleteAgain)
  }

  func testCopiedArtifactOpensFromAnotherDataRoot() async throws {
    let firstStore = MeetingStore(dataRoot: root)
    let manifest = makeManifest()
    try await firstStore.create(manifest)

    let copiedRoot = FileManager.default.temporaryDirectory.appending(
      path: "symmeet-copy-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copiedRoot) }
    try FileManager.default.createDirectory(
      at: copiedRoot.appending(path: "meetings"), withIntermediateDirectories: true)
    let directoryName = manifest.meetingID.uuidString.lowercased()
    try FileManager.default.copyItem(
      at: root.appending(path: "meetings/\(directoryName)"),
      to: copiedRoot.appending(path: "meetings/\(directoryName)")
    )

    let copiedStore = MeetingStore(dataRoot: copiedRoot)
    let copied = try await copiedStore.load(meetingID: directoryName)
    XCTAssertEqual(copied.meetingID, manifest.meetingID)
  }

  private func makeManifest() -> MeetingManifest {
    MeetingManifest(
      meetingID: UUID(),
      source: .imported,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0),
      originalAsset: "audio/original.m4a",
      audioTracks: [
        AudioTrack(trackID: UUID(), kind: .original, relativePath: "audio/original.m4a")
      ],
      language: "en",
      consent: ConsentState(status: .required),
      retention: RetentionMetadata(policy: .keep)
    )
  }
}

private func assertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ handler: (Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expected an error")
  } catch {
    handler(error)
  }
}
