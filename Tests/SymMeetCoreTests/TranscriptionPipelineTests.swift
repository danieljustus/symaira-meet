import Foundation
import XCTest

@testable import SymMeetCore

final class TranscriptionPipelineTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = try makeTemporaryDirectory()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testRunProducesOutcomeAndPersistsSegments() async throws {
    let engine = FakeTranscriptionEngine()
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    let outcome = try await pipeline.run(
      TranscriptionRequestOptions(
        sourceURL: sourceURL,
        title: "Test Meeting",
        language: "en",
        modelID: "tiny",
        modelVersion: "openai_whisper-tiny",
        engineID: "fake"
      ),
      engine: engine
    )

    XCTAssertEqual(outcome.status, .succeeded)
    XCTAssertEqual(outcome.segmentCount, 2)
    XCTAssertEqual(outcome.modelID, "tiny")
    XCTAssertEqual(outcome.engineID, "fake")
    XCTAssertNotNil(outcome.meetingID)
    XCTAssertNotNil(outcome.jobID)

    let segments = try await MeetingStore(dataRoot: root).rawSegments(
      meetingID: outcome.meetingID.uuidString.lowercased())
    XCTAssertEqual(segments.count, 2)
  }

  func testRetryDoesNotDuplicateFinalizedSegments() async throws {
    let engine = FakeTranscriptionEngine()
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    let first = try await pipeline.run(
      TranscriptionRequestOptions(
        sourceURL: sourceURL,
        title: nil,
        language: nil,
        modelID: "tiny",
        modelVersion: "openai_whisper-tiny",
        engineID: "fake"
      ),
      engine: engine
    )
    XCTAssertEqual(first.segmentCount, 2)

    let retried = try await pipeline.retry(
      meetingID: first.meetingID,
      engine: engine,
      modelID: "tiny",
      modelVersion: "openai_whisper-tiny"
    )

    XCTAssertEqual(retried.status, .succeeded)
    XCTAssertEqual(retried.attempt, 2)

    let segments = try await MeetingStore(dataRoot: root).rawSegments(
      meetingID: first.meetingID.uuidString.lowercased())
    XCTAssertEqual(
      segments.count, 2,
      "retry must not duplicate segments that were already finalized")
  }

  func testCancellationProducesTerminalState() async throws {
    let engine = FakeTranscriptionEngine()
    await engine.setOutcome(.cancel)
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    let task = Task {
      try await pipeline.run(
        TranscriptionRequestOptions(
          sourceURL: sourceURL,
          title: nil,
          language: nil,
          modelID: "tiny",
          modelVersion: "openai_whisper-tiny",
          engineID: "fake"
        ),
        engine: engine
      )
    }

    await pipeline.requestCancellation()
    let outcome = try await task.value

    XCTAssertTrue(
      outcome.status == .cancelled || outcome.status == .interrupted,
      "cancelled run must end in cancelled or interrupted, got \(outcome.status.rawValue)")
    XCTAssertNotEqual(outcome.status, .succeeded)
  }

  func testSecondRunCreatesDistinctMeetingWithSameSourceHash() async throws {
    let engine = FakeTranscriptionEngine()
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    let first = try await pipeline.run(
      TranscriptionRequestOptions(
        sourceURL: sourceURL,
        title: nil,
        language: nil,
        modelID: "tiny",
        modelVersion: "openai_whisper-tiny",
        engineID: "fake"
      ),
      engine: engine
    )

    let second = try await pipeline.run(
      TranscriptionRequestOptions(
        sourceURL: sourceURL,
        title: nil,
        language: nil,
        modelID: "tiny",
        modelVersion: "openai_whisper-tiny",
        engineID: "fake"
      ),
      engine: engine
    )

    XCTAssertNotEqual(
      first.meetingID, second.meetingID,
      "each run must create a distinct meeting")
    XCTAssertEqual(
      first.sourceHash, second.sourceHash,
      "same source file must produce the same source hash")
  }

  func testProgressReportsMeetingCreatedAndPhases() async throws {
    let engine = FakeTranscriptionEngine()
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    var progressEvents: [PipelineProgress] = []
    let outcome = try await pipeline.run(
      TranscriptionRequestOptions(
        sourceURL: sourceURL,
        title: nil,
        language: nil,
        modelID: "tiny",
        modelVersion: "openai_whisper-tiny",
        engineID: "fake"
      ),
      engine: engine,
      onProgress: { progress in progressEvents.append(progress) }
    )

    XCTAssertEqual(outcome.status, .succeeded)
    guard case .meetingCreated = progressEvents.first else {
      XCTFail("First progress event must be .meetingCreated")
      return
    }
    let phases = progressEvents.compactMap { event -> TranscriptionPhase? in
      if case .phase(let p) = event { return p }
      return nil
    }
    XCTAssertTrue(phases.contains(.preparing))
    XCTAssertTrue(phases.contains(.transcribing))
  }

  func testEngineFailureRecordsFailureAndThrows() async throws {
    let engine = FakeTranscriptionEngine()
    await engine.setOutcome(.fail)
    let pipeline = TranscriptionPipeline(dataRoot: root)
    let sourceURL = try createDummyAudio()

    do {
      _ = try await pipeline.run(
        TranscriptionRequestOptions(
          sourceURL: sourceURL,
          title: nil,
          language: nil,
          modelID: "tiny",
          modelVersion: "openai_whisper-tiny",
          engineID: "fake"
        ),
        engine: engine
      )
      XCTFail("Expected engine failure")
    } catch PipelineError.engineFailed {
      // expected
    }
  }

  private func createDummyAudio() throws -> URL {
    let url = root.appending(path: "test-audio.wav")
    // Minimal WAV header: 44 bytes + a few samples of silence.
    var data = Data()
    // RIFF header
    data.append(contentsOf: "RIFF".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Array($0) })
    data.append(contentsOf: "WAVE".utf8)
    // fmt sub-chunk
    data.append(contentsOf: "fmt ".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
    // data sub-chunk
    data.append(contentsOf: "data".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(20).littleEndian) { Array($0) })
    // 10 samples of 16-bit PCM silence (2 bytes each = 20 bytes)
    for _ in 0..<10 {
      data.append(contentsOf: withUnsafeBytes(of: Int16(0).littleEndian) { Array($0) })
    }
    try data.write(to: url)
    return url
  }
}

private func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "symmeet-pipeline-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
