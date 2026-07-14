import Foundation
import SymMeetCore
@preconcurrency import WhisperKit

/// Downloads a selected WhisperKit model into ModelStore's staging area and
/// publishes it atomically. Downloads only happen when this method is called.
public actor WhisperKitModelInstaller {
  private let store: ModelStore

  public init(store: ModelStore = ModelStore()) {
    self.store = store
  }

  public func install(
    id: String,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> ModelRecord {
    let descriptor = try await descriptor(for: id)
    let staging = try await store.prepareDownload(for: id)
    let downloadBase = staging.appending(path: "download", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)

    do {
      let downloaded = try await WhisperKit.download(
        variant: descriptor.upstreamRevision,
        downloadBase: downloadBase,
        progressCallback: { value in progress?(value.fractionCompleted) }
      )
      let payload = staging.appending(path: "payload", directoryHint: .isDirectory)
      try FileManager.default.copyItem(at: downloaded, to: payload)
      return try await store.publish(id, from: staging)
    } catch is CancellationError {
      try? FileManager.default.removeItem(at: staging)
      throw CancellationError()
    } catch let error as ModelError {
      try? FileManager.default.removeItem(at: staging)
      throw error
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw WhisperKitEngineError.modelUnavailable
    }
  }

  private func descriptor(for id: String) async throws -> ModelDescriptor {
    let catalog = await store.catalog
    guard let descriptor = catalog.descriptor(for: id) else {
      throw ModelError.unknownModel
    }
    guard descriptor.engineID == "whisperkit" else {
      throw WhisperKitEngineError.unsupportedModel
    }
    return descriptor
  }
}
