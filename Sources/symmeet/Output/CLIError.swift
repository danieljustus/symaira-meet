import Foundation
import SymMeetCapture
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
    if let error = error as? ExportError {
      return CLIError(exitCode: CLIExit.usage.rawValue, message: error.localizedDescription)
    }
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
    if let error = error as? JobError {
      switch error {
      case .notFound, .invalidTransition:
        return CLIError(exitCode: CLIExit.usage.rawValue, message: error.localizedDescription)
      case .lockHeld, .lockNotOwned, .corruptRecord, .notInterrupted, .notRetryable,
        .operationFailed, .alreadyExists:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    if let error = error as? PipelineError {
      return CLIError(
        exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
    }
    if let error = error as? PrivacyError {
      switch error {
      case .invalidInteractiveAttestation, .invalidAuthorizationRecord,
        .authorizationAlreadyUsed, .authorizationExpired:
        return CLIError(
          exitCode: CLIExit.permissionDenied.rawValue, message: error.localizedDescription)
      case .authorizationNotForSession, .localProcessingOnly, .recordingNotActive:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    if let error = error as? CaptureError {
      switch error {
      case .microphoneDenied, .screenRecordingDenied:
        return CLIError(
          exitCode: CLIExit.permissionDenied.rawValue, message: error.localizedDescription)
      case .microphoneRestricted, .screenRecordingUnavailable, .sourceNotFound,
        .osVersionUnsupported, .captureSessionAlreadyActive, .captureSessionNotActive,
        .noAuthorizationRecord, .bufferOverrun, .trackWriteFailed, .interruptedBySystem:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    if let error = error as? AudioError {
      switch error {
      case .notLocalFile, .outsideApprovedPath, .missingFile, .directoryNotAllowed,
        .unsupportedContainer, .unsupportedCodec, .zeroLength, .invalidAudioFormat:
        return CLIError(
          exitCode: CLIExit.usage.rawValue, message: error.localizedDescription)
      case .missingAudioTrack, .protectedMedia, .exceedsByteLimit, .exceedsDurationLimit,
        .destinationExists, .cancelled, .operationFailed:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    if let error = error as? ContractError {
      switch error {
      case .invalidIdentifier, .invalidStateTransition, .invalidTimeRange:
        return CLIError(
          exitCode: CLIExit.usage.rawValue, message: error.localizedDescription)
      case .unsupportedSchemaVersion:
        return CLIError(
          exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
      }
    }
    guard let storeError = error as? StoreError else {
      return CLIError(
        exitCode: CLIExit.runtimeFailure.rawValue, message: error.localizedDescription)
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
