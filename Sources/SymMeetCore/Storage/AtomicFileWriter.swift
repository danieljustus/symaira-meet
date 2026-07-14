import Darwin
import Foundation

enum AtomicFileWriter {
  static func write(_ data: Data, to destination: URL) throws {
    let fileManager = FileManager.default
    let directory = destination.deletingLastPathComponent()
    let temporary = directory.appending(
      path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")

    guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
      throw StoreError.operationFailed
    }

    do {
      let handle = try FileHandle(forWritingTo: temporary)
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()

      guard rename(temporary.path, destination.path) == 0 else {
        throw StoreError.operationFailed
      }

      try synchronize(directory: directory)
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error is StoreError ? error : StoreError.operationFailed
    }
  }

  private static func synchronize(directory: URL) throws {
    let descriptor = open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { throw StoreError.operationFailed }
    defer { _ = close(descriptor) }
    guard fsync(descriptor) == 0 else { throw StoreError.operationFailed }
  }
}
