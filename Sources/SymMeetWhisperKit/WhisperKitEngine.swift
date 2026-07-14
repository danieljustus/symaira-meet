import Foundation
import SymMeetCore
@preconcurrency import WhisperKit

/// The isolated WhisperKit adapter. No WhisperKit type crosses this module's
/// public boundary; callers only observe SymMeetCore contracts.
public actor WhisperKitEngine: TranscriptionEngine {
  public static let declaredCapabilities = EngineCapabilities(
    languages: [],
    supportsAutoDetection: true,
    supportsWordTimestamps: true,
    supportsSegmentTimestamps: true,
    supportsStreaming: false,
    supportsDiarization: false,
    requiredArchitectures: ["arm64"]
  )

  public let engineID = "whisperkit"
  public let capabilities = WhisperKitEngine.declaredCapabilities

  private let modelID: String
  private let whisperKit: WhisperKit

  public init(modelID: String, modelStore: ModelStore = ModelStore()) async throws {
    let record: ModelRecord
    do {
      record = try await modelStore.verify(id: modelID)
    } catch {
      throw WhisperKitEngineError.modelUnavailable
    }
    guard record.descriptor.engineID == "whisperkit" else {
      throw WhisperKitEngineError.unsupportedModel
    }

    let root = await modelStore.root
    let modelFolder = root.appending(path: modelID, directoryHint: .isDirectory)
      .appending(path: "payload", directoryHint: .isDirectory)
    let config = WhisperKitConfig(
      model: record.descriptor.upstreamRevision,
      modelFolder: modelFolder.path,
      verbose: false,
      logLevel: .none,
      load: true,
      download: false
    )
    do {
      whisperKit = try await WhisperKit(config)
    } catch {
      throw WhisperKitEngineError.modelUnavailable
    }
    self.modelID = modelID
  }

  public func transcribe(
    _ request: TranscriptionRequest
  ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish(throwing: WhisperKitEngineError.transcriptionFailed)
          return
        }
        do {
          try await self.run(request, continuation: continuation)
          continuation.finish()
        } catch is CancellationError {
          continuation.yield(
            TranscriptionEvent(type: .phase, phase: .cancelled)
          )
          continuation.finish()
        } catch let error as WhisperKitEngineError {
          continuation.finish(throwing: error)
        } catch {
          continuation.finish(throwing: WhisperKitEngineError.transcriptionFailed)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func run(
    _ request: TranscriptionRequest,
    continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
  ) async throws {
    continuation.yield(TranscriptionEvent(type: .phase, phase: .preparing))

    var samples: [Float] = []
    samples.reserveCapacity(max(0, request.sourceDurationMS * 16))
    for try await chunk in request.audio {
      try Task.checkCancellation()
      samples.append(contentsOf: chunk.samples)
    }
    guard !samples.isEmpty else { throw WhisperKitEngineError.emptyAudio }

    continuation.yield(
      TranscriptionEvent(type: .phase, phase: .transcribing)
    )
    let options = DecodingOptions(
      verbose: false,
      language: request.language,
      detectLanguage: request.language == nil,
      wordTimestamps: true
    )
    let trackID = request.trackID
    let modelID = self.modelID
    let durationMS = request.sourceDurationMS
    let results = try await whisperKit.transcribe(
      audioArray: samples,
      decodeOptions: options,
      segmentCallback: { segments in
        for segment in segments {
          let startMS = max(0, Int((segment.start * 1_000).rounded()))
          let endMS = max(startMS, Int((segment.end * 1_000).rounded()))
          let draft = SegmentDraft(
            trackID: trackID,
            startMS: startMS,
            endMS: endMS,
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          continuation.yield(
            TranscriptionEvent(type: .finalizedSegment, segment: draft)
          )
          if durationMS > 0 {
            continuation.yield(
              TranscriptionEvent(
                type: .progress,
                progress: min(1, max(0, Double(endMS) / Double(durationMS)))
              )
            )
          }
        }
      }
    )
    try Task.checkCancellation()
    guard !results.isEmpty else { throw WhisperKitEngineError.transcriptionFailed }

    let segmentCount = results.reduce(0) { $0 + $1.segments.count }
    continuation.yield(
      TranscriptionEvent(
        type: .checkpoint,
        checkpoint: TranscriptionCheckpoint(
          completedSourceTimeMS: request.sourceDurationMS,
          engineID: engineID,
          modelID: modelID
        )
      )
    )
    continuation.yield(
      TranscriptionEvent(
        type: .completed,
        completion: TranscriptionCompletion(
          segmentCount: segmentCount,
          language: results.first?.language,
          durationMS: request.sourceDurationMS
        )
      )
    )
  }
}
