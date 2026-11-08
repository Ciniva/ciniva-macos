// Prints the base64 Ed25519 signature of a file. The private key (base64, raw) comes from UPDATE_SIGNING_KEY.
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"] ?? ""
guard CommandLine.arguments.count == 2, let raw = Data(base64Encoded: env.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else {
    FileHandle.standardError.write(Data("usage: UPDATE_SIGNING_KEY=… sign-update.swift <file>\n".utf8))
    exit(1)
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print(try key.signature(for: data).base64EncodedString())
