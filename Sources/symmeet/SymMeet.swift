import ArgumentParser
import Foundation
import SymMeetCore

@main
struct SymMeet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "symmeet",
    abstract: "Local-first meeting artifacts and processing.",
    subcommands: [Version.self]
  )
}

extension SymMeet {
  struct Version: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Print the symmeet version."
    )

    func run() throws {
      print("symmeet 0.1.0-dev (schema \(SymMeetCore.schemaVersion))")
    }
  }
}
