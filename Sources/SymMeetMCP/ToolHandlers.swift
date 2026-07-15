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

// MARK: - Meeting List Handler

struct MeetingListHandler: MCPToolHandler {
  let toolName = "meeting_list"

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    let store = MeetingStore()
    let result = try await store.list()

    let output = MeetingListOutput(
      meetings: result.meetings.map { manifest in
        MeetingSummary(
          meetingID: manifest.meetingID.uuidString.lowercased(),
          source: manifest.source.rawValue,
          createdAt: manifest.createdAt,
          language: manifest.language,
          jobState: manifest.job?.state.rawValue
        )
      },
      diagnostics: result.diagnostics.map { diag in
        DiagnosticOutput(meetingID: diag.meetingID, code: diag.code.rawValue)
      }
    )

    let data = try makeEncoder().encode(output)
    return .text(String(decoding: data, as: UTF8.self))
  }
}

// MARK: - Meeting Get Handler

struct MeetingGetHandler: MCPToolHandler {
  let toolName = "meeting_get"
  let maxSegments = 500

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let meetingID = args["meeting_id"]?.asString else {
      return .error("Missing required parameter: meeting_id")
    }

    let store = MeetingStore()
    let manifest = try await store.load(meetingID: meetingID)

    let includeSegments = args["include_segments"]?.asBool ?? false
    let segmentLimit = min(args["segment_limit"]?.asInt ?? 50, maxSegments)

    var output = MeetingGetOutput(
      meetingID: manifest.meetingID.uuidString.lowercased(),
      source: manifest.source.rawValue,
      createdAt: manifest.createdAt,
      updatedAt: manifest.updatedAt,
      language: manifest.language,
      job: manifest.job.map { JobOutput(jobID: $0.jobID.uuidString.lowercased(), state: $0.state.rawValue) },
      consent: ConsentOutput(status: manifest.consent.status.rawValue),
      retention: RetentionOutput(policy: manifest.retention.policy.rawValue)
    )

    if includeSegments {
      let segments = try await store.rawSegments(meetingID: meetingID)
      let bounded = Array(segments.prefix(segmentLimit))
      output.segments = bounded.map { seg in
        SegmentOutput(
          segmentID: seg.segmentID.uuidString.lowercased(),
          speakerID: seg.speakerID,
          startMS: seg.startMS,
          endMS: seg.endMS,
          text: seg.editedText ?? seg.engineText,
          revision: seg.revision.rawValue
        )
      }
      output.segmentCount = segments.count
      output.segmentLimit = segmentLimit
    }

    let data = try makeEncoder().encode(output)
    return .text(String(decoding: data, as: UTF8.self))
  }
}

// MARK: - Meeting Transcribe Handler

struct MeetingTranscribeHandler: MCPToolHandler {
  let toolName = "meeting_transcribe"

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let file = args["file"]?.asString else {
      return .error("Missing required parameter: file")
    }

    guard FileManager.default.fileExists(atPath: file) else {
      return .error("File not found: \(file)")
    }

    let model = args["model"]?.asString ?? "tiny"
    let paths = SymMeetPaths()
    let modelStore = ModelStore()

    do {
      _ = try await modelStore.verify(id: model)
    } catch ModelError.modelNotInstalled {
      return .error("Model '\(model)' is not installed. Run: symmeet model install \(model)")
    } catch {
      return .error("Model verification failed: \(error.localizedDescription)")
    }

    let pipeline = TranscriptionPipeline(dataRoot: paths.dataDirectory)
    let sourceURL = URL(fileURLWithPath: file)
    let languageValue = (args["language"]?.asString ?? "auto") == "auto" ? nil : args["language"]?.asString
    let title = args["title"]?.asString

    do {
      let outcome = try await pipeline.run(
        TranscriptionRequestOptions(
          sourceURL: sourceURL,
          title: title,
          language: languageValue,
          modelID: model,
          modelVersion: "",
          engineID: "whisperkit"
        ),
        engine: StubEngine()
      )

      let result = TranscribeResultOutput(
        meetingID: outcome.meetingID.uuidString.lowercased(),
        jobID: outcome.jobID.uuidString.lowercased(),
        state: outcome.status.rawValue,
        segmentCount: outcome.segmentCount,
        language: outcome.language
      )
      let data = try makeEncoder().encode(result)
      return .text(String(decoding: data, as: UTF8.self))
    } catch {
      return .error("Transcription failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - Meeting Job Status Handler

struct MeetingJobStatusHandler: MCPToolHandler {
  let toolName = "meeting_job_status"

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let jobID = args["job_id"]?.asString else {
      return .error("Missing required parameter: job_id")
    }

    let paths = SymMeetPaths()
    let coordinator = JobCoordinator(dataRoot: paths.dataDirectory)
    let job = try await resolveJob(coordinator: coordinator, identifier: jobID)

    let output = JobStatusOutput(
      jobID: job.jobID.uuidString.lowercased(),
      meetingID: job.meetingID.uuidString.lowercased(),
      status: job.status.rawValue,
      attempt: job.attempt,
      engine: job.engine.map {
        EngineOutput(engineID: $0.engineID, modelID: $0.modelID)
      }
    )

    let data = try makeEncoder().encode(output)
    return .text(String(decoding: data, as: UTF8.self))
  }
}

// MARK: - Meeting Job Cancel Handler

struct MeetingJobCancelHandler: MCPToolHandler {
  let toolName = "meeting_job_cancel"

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let jobID = args["job_id"]?.asString else {
      return .error("Missing required parameter: job_id")
    }

    let paths = SymMeetPaths()
    let coordinator = JobCoordinator(dataRoot: paths.dataDirectory)
    let job = try await resolveJob(coordinator: coordinator, identifier: jobID)

    guard job.status == .queued || job.status.isActive else {
      return .text(
        "{\"status\":\"\(job.status.rawValue)\",\"message\":\"Job is already in terminal state.\"}")
    }

    let handle = try await coordinator.lock.acquire(meetingID: job.meetingID)
    if job.status == .queued {
      _ = try await coordinator.advance(
        meetingID: job.meetingID, to: .cancelled, using: handle,
        note: "cancelled via MCP")
    } else {
      _ = try await coordinator.requestCancellation(meetingID: job.meetingID, using: handle)
      _ = try await coordinator.confirmCancelled(meetingID: job.meetingID, using: handle)
    }

    return .text(
      "{\"meeting_id\":\"\(job.meetingID.uuidString.lowercased())\",\"status\":\"cancelled\",\"message\":\"Job cancelled.\"}"
    )
  }
}

// MARK: - Meeting Export Handler

struct MeetingExportHandler: MCPToolHandler {
  let toolName = "meeting_export"

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let meetingID = args["meeting_id"]?.asString else {
      return .error("Missing required parameter: meeting_id")
    }
    guard let formatStr = args["format"]?.asString,
      let format = ExportFormat(rawValue: formatStr)
    else {
      return .error(
        "Invalid format. Supported: \(ExportFormat.allCases.map(\.rawValue).joined(separator: ", "))")
    }

    let store = MeetingStore()
    let manifest = try await store.load(meetingID: meetingID)

    if manifest.job?.state != .completed {
      return .error(
        "Meeting transcription is not complete (state: \(manifest.job?.state.rawValue ?? "not_started"))."
      )
    }

    var requestedSource: ExportSegmentSource?
    if let segmentsStr = args["segments"]?.asString {
      guard let parsed = ExportSegmentSource(rawValue: segmentsStr) else {
        return .error("Invalid segment source. Supported: raw, edited.")
      }
      requestedSource = parsed
    }

    let segments: [Segment]
    let segmentSource: ExportSegmentSource

    if let requested = requestedSource {
      switch requested {
      case .raw:
        segments = try await store.rawSegments(meetingID: meetingID)
        segmentSource = .raw
      case .edited:
        let edited = try await store.editedSegments(meetingID: meetingID)
        guard !edited.isEmpty else {
          return .error("Edited segments are unavailable for this meeting.")
        }
        segments = edited
        segmentSource = .edited
      }
    } else {
      let edited = try await store.editedSegments(meetingID: meetingID)
      if !edited.isEmpty {
        segments = edited
        segmentSource = .edited
      } else {
        segments = try await store.rawSegments(meetingID: meetingID)
        segmentSource = .raw
      }
    }

    let content = try TranscriptRenderer.render(
      manifest: manifest,
      segments: segments,
      segmentSource: segmentSource,
      format: format,
      options: TranscriptRenderer.Options(withTimestamps: false)
    )

    let output = ExportOutput(
      meetingID: meetingID.lowercased(),
      format: format.rawValue,
      segmentSource: segmentSource.rawValue,
      segmentCount: segments.count,
      content: content
    )
    let data = try makeEncoder().encode(output)
    return .text(String(decoding: data, as: UTF8.self))
  }
}

// MARK: - Meeting Recording Status Handler

struct MeetingRecordingStatusHandler: MCPToolHandler {
  let toolName = "meeting_recording_status"
  let agentBridge: AgentBridge

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    do {
      let status = try await agentBridge.queryRecordingStatus()
      let data = try makeEncoder().encode(status)
      return .text(String(decoding: data, as: UTF8.self))
    } catch AgentBridgeError.agentUnavailable {
      return .error(
        "No recording agent is available. Recordings must be managed through the SymMeetAgent app.")
    }
  }
}

// MARK: - Meeting Recording Request Handler

struct MeetingRecordingRequestHandler: MCPToolHandler {
  let toolName = "meeting_recording_request"
  let agentBridge: AgentBridge

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    guard let purpose = args["purpose"]?.asString, !purpose.isEmpty else {
      return .error("Missing required parameter: purpose")
    }

    let hasConsentField = args["consent"] != nil || args["consented"] != nil
      || args["authorization_token"] != nil
    if hasConsentField {
      return .error(
        "Consent fields are not accepted. Recording authorization requires interactive human confirmation through the SymMeetAgent."
      )
    }

    do {
      let request = try await agentBridge.requestRecording(purpose: purpose)
      let data = try makeEncoder().encode(request)
      return .text(String(decoding: data, as: UTF8.self))
    } catch AgentBridgeError.agentUnavailable {
      return .error(
        "Recording agent is unavailable. Cannot start recording without an authorized agent. Do not fall back to direct CLI capture.")
    }
  }
}

// MARK: - Meeting Recording Stop Handler

struct MeetingRecordingStopHandler: MCPToolHandler {
  let toolName = "meeting_recording_stop"
  let agentBridge: AgentBridge

  func execute(args: [String: AnyCodable]) async throws -> MCPToolResult {
    do {
      let result = try await agentBridge.stopRecording()
      let data = try makeEncoder().encode(result)
      return .text(String(decoding: data, as: UTF8.self))
    } catch AgentBridgeError.agentUnavailable {
      return .error("No recording agent is available to stop.")
    } catch AgentBridgeError.noActiveRecording {
      return .error("No active recording to stop.")
    }
  }
}

// MARK: - Stub engine for MCP transcription

/// A minimal engine stub used by the MCP transcribe handler.
/// This satisfies the TranscriptionEngine Actor protocol without pulling
/// in SymMeetWhisperKit. The pipeline will create the meeting artifact
/// and job but the engine produces no segments.
private actor StubEngine: TranscriptionEngine {
  let engineID = "stub"
  let capabilities = EngineCapabilities(
    languages: [],
    supportsAutoDetection: false,
    supportsWordTimestamps: false,
    supportsSegmentTimestamps: false,
    supportsStreaming: false,
    supportsDiarization: false,
    requiredArchitectures: []
  )

  func transcribe(
    _ request: TranscriptionRequest
  ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

// MARK: - Output types

private struct MeetingListOutput: Encodable {
  let meetings: [MeetingSummary]
  let diagnostics: [DiagnosticOutput]
}

private struct MeetingSummary: Encodable {
  let meetingID: String
  let source: String
  let createdAt: Date
  let language: String?
  let jobState: String?

  private enum CodingKeys: String, CodingKey {
    case meetingID = "meeting_id"
    case source
    case createdAt = "created_at"
    case language
    case jobState = "job_state"
  }
}

private struct DiagnosticOutput: Encodable {
  let meetingID: String
  let code: String

  private enum CodingKeys: String, CodingKey {
    case meetingID = "meeting_id"
    case code
  }
}

private struct MeetingGetOutput: Encodable {
  let meetingID: String
  let source: String
  let createdAt: Date
  let updatedAt: Date
  let language: String?
  let job: JobOutput?
  let consent: ConsentOutput
  let retention: RetentionOutput
  var segments: [SegmentOutput]?
  var segmentCount: Int?
  var segmentLimit: Int?

  private enum CodingKeys: String, CodingKey {
    case meetingID = "meeting_id"
    case source, createdAt = "created_at", updatedAt = "updated_at"
    case language, job, consent, retention, segments
    case segmentCount = "segment_count"
    case segmentLimit = "segment_limit"
  }
}

private struct JobOutput: Encodable {
  let jobID: String
  let state: String

  private enum CodingKeys: String, CodingKey {
    case jobID = "job_id"
    case state
  }
}

private struct ConsentOutput: Encodable {
  let status: String
}

private struct RetentionOutput: Encodable {
  let policy: String
}

private struct SegmentOutput: Encodable {
  let segmentID: String
  let speakerID: String
  let startMS: Int
  let endMS: Int
  let text: String
  let revision: String

  private enum CodingKeys: String, CodingKey {
    case segmentID = "segment_id"
    case speakerID = "speaker_id"
    case startMS = "start_ms"
    case endMS = "end_ms"
    case text, revision
  }
}

private struct TranscribeResultOutput: Encodable {
  let meetingID: String
  let jobID: String
  let state: String
  let segmentCount: Int
  let language: String?

  private enum CodingKeys: String, CodingKey {
    case meetingID = "meeting_id"
    case jobID = "job_id"
    case state, segmentCount = "segment_count", language
  }
}

private struct JobStatusOutput: Encodable {
  let jobID: String
  let meetingID: String
  let status: String
  let attempt: Int
  let engine: EngineOutput?

  private enum CodingKeys: String, CodingKey {
    case jobID = "job_id"
    case meetingID = "meeting_id"
    case status, attempt, engine
  }
}

private struct EngineOutput: Encodable {
  let engineID: String
  let modelID: String

  private enum CodingKeys: String, CodingKey {
    case engineID = "engine_id"
    case modelID = "model_id"
  }
}

private struct ExportOutput: Encodable {
  let meetingID: String
  let format: String
  let segmentSource: String
  let segmentCount: Int
  let content: String

  private enum CodingKeys: String, CodingKey {
    case meetingID = "meeting_id"
    case format, segmentSource = "segment_source"
    case segmentCount = "segment_count", content
  }
}

// MARK: - Shared helpers

private func resolveJob(coordinator: JobCoordinator, identifier: String) async throws
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
