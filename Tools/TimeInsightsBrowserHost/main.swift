import Darwin
import Foundation

// Chrome and Edge pass the extension origin as their first argument. The per-browser
// manifests point to distinct copies of this helper, so the extension cannot claim a bundle ID.
let browser: String
switch URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent {
case "dockling-chrome-host": browser = "com.google.Chrome"
case "dockling-edge-host": browser = "com.microsoft.edgemac"
default: exit(1)
}
let sender = UUID().uuidString
let input = FileHandle.standardInput
let output = FileHandle.standardOutput
signal(SIGPIPE, SIG_IGN)

func readExactly(_ count: Int) throws -> Data? {
    var result = Data()
    while result.count < count {
        guard let next = try input.read(upToCount: count - result.count), !next.isEmpty else { return nil }
        result.append(next)
    }
    return result
}

func request(_ data: Data) throws -> String? {
    let path = NSTemporaryDirectory() + (NSTemporaryDirectory().hasSuffix("/") ? "" : "/")
        + "com.docket-zh.time-insights/host.sock"
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8CString)
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        pathBytes.withUnsafeBytes { destination.copyBytes(from: $0) }
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
    for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
        setsockopt(fd, SOL_SOCKET, option, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return nil }
    try handle.write(contentsOf: data + Data([10]))
    var response = Data()
    while response.count < 64, let byte = try handle.read(upToCount: 1), !byte.isEmpty {
        if byte == Data([10]) {
            let value = String(decoding: response, as: UTF8.self)
            return UUID(uuidString: value)?.uuidString
        }
        response.append(byte)
    }
    return nil
}

while let header = try readExactly(4) {
    let count = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
    guard (1...1024).contains(count), let body = try readExactly(count),
          var message = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { break }
    message["browser"] = browser
    message["sender"] = sender
    let payload = try JSONSerialization.data(withJSONObject: message)
    let lease = try? request(payload)
    let response = try JSONSerialization.data(withJSONObject: ["lease": lease ?? ""])
    var size = UInt32(response.count).littleEndian
    try output.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
    try output.write(contentsOf: response)
}
