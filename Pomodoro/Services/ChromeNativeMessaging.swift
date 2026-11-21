import CoreFoundation
import Darwin
import Foundation

enum ChromeNativeMessaging {
    private static let hostName = "com.ruidouwang.pomodoro.focus"
    private static let extensionID = "dkhlkcjdcenjdoekindkpjikhhllhfjb"
    private static var origin: String { "chrome-extension://\(extensionID)/" }
    private static var portName: CFString { "\(hostName).v1.\(getuid())" as CFString }
    static let launchArgument = "--chrome-native-host"

    struct Request: Codable {
        var client = UUID()
        var ready: Bool
        var host: String?
        var roundID: UUID?
    }

    struct WebException: Codable {
        let host: String
        let endsAt: Date
    }

    struct WebState: Codable {
        let roundID: UUID
        let endsAt: Date
        let mode: FocusLimitMode
        let domains: [String]
        let exception: WebException?
    }

    struct Reply: Codable {
        var version = 1
        var state: WebState?
    }

    static func listen() -> CFMessagePort? {
        let port = CFMessagePortCreateLocal(nil, portName, { _, _, data, _ in
            guard let data,
                  let request = try? JSONDecoder().decode(Request.self, from: data as Data) else {
                return nil
            }
            let reply = MainActor.assumeIsolated { FocusLimitService.shared.handleChrome(request) }
            guard let encoded = try? ChromeNativeMessaging.encode(reply) else { return nil }
            return Unmanaged.passRetained(encoded as CFData)
        }, nil, nil)
        guard let port, let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        return port
    }

    static func register() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let support = library.appendingPathComponent("Application Support")
        let launcherFolder = support.appendingPathComponent("com.ruidouwang.Pomodoro/Chrome")
        let manifests = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts")
        try FileManager.default.createDirectory(at: launcherFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)

        let launcher = launcherFolder.appendingPathComponent("native-host")
        let quotedExecutable = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try "#!/bin/sh\nexec \(quotedExecutable) \(launchArgument) \"$@\"\n"
            .write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)

        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Pomodoro Chrome focus limits",
            "path": launcher.path,
            "type": "stdio",
            "allowed_origins": [origin]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifests.appendingPathComponent(hostName + ".json"), options: .atomic)
    }

    static func runHost(arguments: [String]) throws {
        guard arguments.dropFirst(2).first == origin else { return }
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        let fallback = try encode(Reply())
        var descriptor = pollfd(fd: input.fileDescriptor, events: Int16(POLLIN), revents: 0)
        var request = Request(ready: false)
        var lastReply: Data?
        var remote: CFMessagePort?

        while true {
            let result = poll(&descriptor, 1, 500)
            if result < 0 {
                if errno == EINTR { continue }
                return
            }
            if result > 0 {
                guard descriptor.revents & Int16(POLLIN) != 0,
                      let size = try read(4, from: input) else { return }
                let length = Int(size.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                guard (1...4096).contains(length), let body = try read(length, from: input) else { return }
                if let incoming = try? JSONDecoder().decode(BrowserMessage.self, from: body) {
                    request.ready = incoming.ready
                    request.host = incoming.host
                    request.roundID = incoming.roundID
                }
            }

            if remote == nil { remote = CFMessagePortCreateRemote(nil, portName) }
            var reply = fallback
            if let port = remote {
                var data: Unmanaged<CFData>?
                let message = try encode(request)
                let status = CFMessagePortSendRequest(
                    port, 1, message as CFData, 0.2, 0.2, CFRunLoopMode.defaultMode.rawValue, &data
                )
                if status == kCFMessagePortSuccess, let data {
                    reply = data.takeRetainedValue() as Data
                } else {
                    remote = nil
                }
            }
            request.host = nil
            request.roundID = nil
            if lastReply != reply {
                var length = UInt32(reply.count)
                try output.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) })
                try output.write(contentsOf: reply)
                lastReply = reply
            }
        }
    }

    private struct BrowserMessage: Decodable {
        let ready: Bool
        let host: String?
        let roundID: UUID?
    }

    private static func read(_ length: Int, from file: FileHandle) throws -> Data? {
        var data = Data()
        while data.count < length {
            guard let chunk = try file.read(upToCount: length - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
