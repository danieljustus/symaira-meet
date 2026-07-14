import Foundation

/// An actor-backed filesystem store for portable meeting artifacts.
public actor MeetingStore {
  public let layout: ArtifactLayout

  public init(dataRoot: URL = SymMeetPaths().dataDirectory) {
    layout = ArtifactLayout(dataRoot: dataRoot)
  }

  public func create(_ manifest: MeetingManifest) throws {
    try validateManifestPaths(manifest)
    let meetingID = manifest.meetingID.uuidString.lowercased()
    try validateMeetingID(meetingID)
    try prepareDirectory(layout.meetingsDirectory)

    let directory = layout.meetingDirectory(meetingID)
    try requireSafePath(directory)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw StoreError.alreadyExists
    }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      try writeInitialFiles(for: manifest, in: directory)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  public func load(meetingID: String) throws -> MeetingManifest {
    let normalizedID = try normalizedMeetingID(meetingID)
    let directory = layout.meetingDirectory(normalizedID)
    try requireExistingSafeDirectory(directory)

    let manifestURL = layout.manifestURL(in: directory)
    try requireSafePath(manifestURL)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw StoreError.malformedArtifact
    }

    do {
      let manifest = try ContractCodec.decoder().decode(
        MeetingManifest.self, from: Data(contentsOf: manifestURL))
      guard manifest.meetingID.uuidString.lowercased() == normalizedID else {
        throw StoreError.malformedArtifact
      }
      try validateManifestPaths(manifest)
      return manifest
    } catch {
      throw error is StoreError ? error : StoreError.malformedArtifact
    }
  }

  public func update(_ manifest: MeetingManifest) throws {
    try validateManifestPaths(manifest)
    let meetingID = manifest.meetingID.uuidString.lowercased()
    let directory = layout.meetingDirectory(meetingID)
    try requireExistingSafeDirectory(directory)

    do {
      let data = try ContractCodec.encoder(prettyPrinted: true).encode(manifest)
      try AtomicFileWriter.write(data, to: layout.manifestURL(in: directory))
    } catch {
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  public func list() throws -> MeetingList {
    try prepareDirectory(layout.meetingsDirectory)
    let entries: [URL]

    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: layout.meetingsDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      throw StoreError.operationFailed
    }

    var meetings: [MeetingManifest] = []
    var diagnostics: [StoreDiagnostic] = []

    for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let meetingID = entry.lastPathComponent
      guard UUID(uuidString: meetingID) != nil else {
        diagnostics.append(StoreDiagnostic(meetingID: meetingID, code: .invalidMeetingDirectory))
        continue
      }

      do {
        try requireExistingSafeDirectory(entry)
        meetings.append(try load(meetingID: meetingID))
      } catch StoreError.unsafePath {
        diagnostics.append(StoreDiagnostic(meetingID: meetingID, code: .unsafePath))
      } catch {
        diagnostics.append(StoreDiagnostic(meetingID: meetingID, code: .malformedManifest))
      }
    }

    return MeetingList(meetings: meetings, diagnostics: diagnostics)
  }

  public func append(_ event: EventEnvelope) throws {
    let meetingID = event.meetingID.uuidString.lowercased()
    let directory = layout.meetingDirectory(meetingID)
    try requireExistingSafeDirectory(directory)

    let eventsURL = layout.eventsURL(in: directory)
    try requireSafePath(eventsURL)
    let existing = (try? Data(contentsOf: eventsURL)) ?? Data()

    do {
      let eventData = try ContractCodec.encoder().encode(event)
      var updated = existing
      updated.append(eventData)
      updated.append(0x0A)
      try AtomicFileWriter.write(updated, to: eventsURL)
    } catch {
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  /// Appends one finalized segment to the meeting's `segments.raw.jsonl`
  /// evidence file. Engine output is immutable evidence, so this file is
  /// append-only -- callers that need to avoid persisting the same segment
  /// twice across a retry must dedupe before calling this (see
  /// ``SegmentAccumulator``).
  public func appendRawSegment(_ segment: Segment, meetingID: String) throws {
    let normalizedID = try normalizedMeetingID(meetingID)
    let directory = layout.meetingDirectory(normalizedID)
    try requireExistingSafeDirectory(directory)

    let segmentsURL = layout.rawSegmentsURL(in: directory)
    try requireSafePath(segmentsURL)
    let existing = (try? Data(contentsOf: segmentsURL)) ?? Data()

    do {
      let segmentData = try ContractCodec.encoder().encode(segment)
      var updated = existing
      updated.append(segmentData)
      updated.append(0x0A)
      try AtomicFileWriter.write(updated, to: segmentsURL)
    } catch {
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  /// Reads back every segment already finalized in `segments.raw.jsonl`, in
  /// the order they were written. Used to seed ``SegmentAccumulator`` before
  /// a retry so already-finalized time ranges are never persisted twice.
  public func rawSegments(meetingID: String) throws -> [Segment] {
    let normalizedID = try normalizedMeetingID(meetingID)
    let directory = layout.meetingDirectory(normalizedID)
    try requireExistingSafeDirectory(directory)

    let segmentsURL = layout.rawSegmentsURL(in: directory)
    try requireSafePath(segmentsURL)
    guard let data = try? Data(contentsOf: segmentsURL), !data.isEmpty else { return [] }

    do {
      return try data.split(separator: 0x0A).map {
        try ContractCodec.decoder().decode(Segment.self, from: Data($0))
      }
    } catch {
      throw StoreError.malformedArtifact
    }
  }

  /// Returns the derived files eligible for a retention cleanup after validating
  /// that every path remains under the configured data root.
  public func derivedArtifactURLs(meetingID: String) throws -> [URL] {
    let normalizedID = try normalizedMeetingID(meetingID)
    let directory = layout.meetingDirectory(normalizedID)
    try requireExistingSafeDirectory(directory)

    let audioDirectory = directory.appending(path: "audio", directoryHint: .isDirectory)
    let candidates = [
      layout.rawSegmentsURL(in: directory),
      layout.editedSegmentsURL(in: directory),
      layout.transcriptURL(in: directory),
      audioDirectory.appending(path: "normalized.caf", directoryHint: .notDirectory),
      audioDirectory.appending(path: "normalized", directoryHint: .isDirectory),
    ]
    for candidate in candidates {
      try requireSafePath(candidate)
    }
    return candidates
  }

  public func trash(meetingID: String) throws {
    let normalizedID = try normalizedMeetingID(meetingID)
    let source = layout.meetingDirectory(normalizedID)
    let destination = layout.trashedMeetingDirectory(normalizedID)
    try requireExistingSafeDirectory(source)
    try prepareDirectory(layout.trashDirectory)
    try requireSafePath(destination)

    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw StoreError.operationFailed
    }
    try move(source, to: destination)
  }

  public func restore(meetingID: String) throws {
    let normalizedID = try normalizedMeetingID(meetingID)
    let source = layout.trashedMeetingDirectory(normalizedID)
    let destination = layout.meetingDirectory(normalizedID)
    try requireExistingSafeDirectory(source)
    try prepareDirectory(layout.meetingsDirectory)
    try requireSafePath(destination)

    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw StoreError.alreadyExists
    }
    try move(source, to: destination)
  }

  /// Permanently deletes an already-trashed meeting. The operation is idempotent.
  @discardableResult
  public func permanentlyDelete(meetingID: String) throws -> Bool {
    let normalizedID = try normalizedMeetingID(meetingID)
    let directory = layout.trashedMeetingDirectory(normalizedID)
    try requireSafePath(directory)

    guard FileManager.default.fileExists(atPath: directory.path) else { return false }
    try requireExistingSafeDirectory(directory)

    do {
      try FileManager.default.removeItem(at: directory)
      return true
    } catch {
      throw StoreError.operationFailed
    }
  }

  private func writeInitialFiles(for manifest: MeetingManifest, in directory: URL) throws {
    let manifestData = try ContractCodec.encoder(prettyPrinted: true).encode(manifest)
    try AtomicFileWriter.write(manifestData, to: layout.manifestURL(in: directory))
    try AtomicFileWriter.write(Data(), to: layout.eventsURL(in: directory))
    try AtomicFileWriter.write(Data(), to: layout.rawSegmentsURL(in: directory))
    try AtomicFileWriter.write(Data(), to: layout.editedSegmentsURL(in: directory))
    try AtomicFileWriter.write(
      Data(
        "## Summary\n\n## Decisions\n\n## Action Items\n\n## Participants\n\n## Transcript\n".utf8),
      to: layout.transcriptURL(in: directory)
    )
  }

  private func move(_ source: URL, to destination: URL) throws {
    do {
      try FileManager.default.moveItem(at: source, to: destination)
    } catch {
      throw StoreError.operationFailed
    }
  }

  private func normalizedMeetingID(_ value: String) throws -> String {
    guard let uuid = UUID(uuidString: value) else { throw StoreError.invalidMeetingID }
    return uuid.uuidString.lowercased()
  }

  private func validateMeetingID(_ value: String) throws {
    guard UUID(uuidString: value) != nil else { throw StoreError.invalidMeetingID }
  }

  private func validateManifestPaths(_ manifest: MeetingManifest) throws {
    if let originalAsset = manifest.originalAsset {
      try validateRelativePath(originalAsset)
    }
    for track in manifest.audioTracks {
      try validateRelativePath(track.relativePath)
    }
  }

  private func validateRelativePath(_ value: String) throws {
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    guard
      !value.isEmpty,
      !value.hasPrefix("/"),
      !value.hasPrefix("~"),
      !components.contains(""),
      !components.contains("..")
    else {
      throw StoreError.invalidRelativePath
    }
  }

  private func prepareDirectory(_ directory: URL) throws {
    try requireSafePath(directory)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try requireSafePath(directory)
    } catch {
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  private func requireExistingSafeDirectory(_ directory: URL) throws {
    try requireSafePath(directory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw StoreError.missing
    }
  }

  private func requireSafePath(_ candidate: URL) throws {
    let root = layout.dataRoot.standardizedFileURL
    let path = candidate.standardizedFileURL
    let rootPath = root.path
    guard path.path == rootPath || path.path.hasPrefix(rootPath + "/") else {
      throw StoreError.unsafePath
    }

    var current = root
    if FileManager.default.fileExists(atPath: current.path), try isSymbolicLink(current) {
      throw StoreError.unsafePath
    }

    let relative = path.path.dropFirst(rootPath.count).split(separator: "/")
    for component in relative {
      current.append(path: String(component), directoryHint: .isDirectory)
      if FileManager.default.fileExists(atPath: current.path), try isSymbolicLink(current) {
        throw StoreError.unsafePath
      }
    }
  }

  private func isSymbolicLink(_ url: URL) throws -> Bool {
    do {
      return try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
    } catch {
      throw StoreError.operationFailed
    }
  }
}
