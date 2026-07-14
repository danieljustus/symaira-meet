@preconcurrency import ArgumentParser
import Darwin

@main
struct SymMeet: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "symmeet",
    abstract: "Local-first meeting artifacts and processing.",
    subcommands: [Version.self, Doctor.self, Configuration.self, Meeting.self, Completion.self]
  )

  static func main() async {
    do {
      var command = try parseAsRoot()
      if var asyncCommand = command as? any AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch let error as CleanExit {
      Self.exit(withError: error)
    } catch let error as CLIError {
      Output.writeError(error.message)
      Darwin.exit(error.exitCode)
    } catch {
      Output.writeError("Usage error: \(error)")
      Darwin.exit(CLIExit.usage.rawValue)
    }
  }
}
