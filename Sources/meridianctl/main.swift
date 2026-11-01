import Foundation
import MeridianKit
import MeridianSensors

// meridianctl: terminal probe for the telemetry module. No dependencies, hand-rolled argv.

let usage = """
meridianctl <command>

  snapshot            one telemetry snapshot as pretty JSON (default)
  watch [seconds]     one compact line per second until interrupted (optional count)
  sensors             temperatures with group and source (hid or smc)
  smc-keys            every SMC key with type, raw bytes and decoded value
  contribute [--out PATH]
                      write meridian-sensors-<chip>.json (default: ~/Desktop) for a chip-mapping pull request
  help                this text
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "snapshot" : arguments.removeFirst()

switch command {
case "snapshot": await Commands.snapshot()
case "watch": await Commands.watch(count: arguments.first.flatMap(Int.init))
case "sensors": Commands.sensors()
case "smc-keys": Commands.smcKeys()
case "contribute": Commands.contribute(arguments: arguments)
case "help", "-h", "--help": print(usage)
default:
    FileHandle.standardError.write(Data("unknown command '\(command)'\n\n\(usage)\n".utf8))
    exit(2)
}
