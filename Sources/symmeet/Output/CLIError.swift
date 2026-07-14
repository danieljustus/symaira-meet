import Foundation
import SymMeetCore
import SymMeetWhisperKit

enum CLIExit: Int32 {
  case success = 0
  case runtimeFailure = 1
  case usage = 2
  case permissionDenied = 3
  case unsupported = 4
}

struct CLIError: Error {
  let exitCode: Int32
  let message: String

  static func from(_ error: Error) -> CLIError {
    if let error = error as? CLIError { return error }
    if let error = error as? ModelError {
      switch error {
      case .invalidIdentifier, .unknownModel:
        return CLIError(exitCode: CLIExit.usage.rawValue, message: error.localizedDescription)
      case .modelNotInstalled, .corruptModel, .incompatibleModel, .inUse, .invalidSource,
        .operationFailed:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    if let error = error as? WhisperKitEngineError {
      return CLIError(
        exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
    }
    guard let storeError = error as? StoreError else {
      return CLIError(exitCode: CLIExit.runtimeFailure.rawValue, message: "Command failed.")
    }

    switch storeError {
    case .invalidMeetingID, .invalidRelativePath:
      return CLIError(exitCode: CLIExit.usage.rawValue, message: storeError.localizedDescription)
    case .unsafePath:
      return CLIError(
        exitCode: CLIExit.permissionDenied.rawValue,
        message: "Access to the requested artifact was denied.")
    case .alreadyExists, .malformedArtifact, .missing, .operationFailed:
      return CLIError(
        exitCode: CLIExit.runtimeFailure.rawValue, message: storeError.localizedDescription)
    }
  }

  static func unsupported(_ message: String) -> CLIError {
    CLIError(exitCode: CLIExit.unsupported.rawValue, message: message)
  }
}
