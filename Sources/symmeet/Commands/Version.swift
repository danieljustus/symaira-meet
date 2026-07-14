import ArgumentParser
import SymMeetCore

extension SymMeet {
  struct Version: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the symmeet version.")

    @Flag(name: .long, help: "Emit the stable machine-readable version handshake.")
    var json = false

    mutating func run() async throws {
      if json {
        Output.writeRaw(
          "{\"tool\":\"symmeet\",\"version\":\"\(BuildInfo.version)\",\"schema_version\":\(SymMeetCore.schemaVersion)}\n"
        )
      } else {
        Output.writeLine("symmeet \(BuildInfo.version) (schema \(SymMeetCore.schemaVersion))")
      }
    }
  }
}
