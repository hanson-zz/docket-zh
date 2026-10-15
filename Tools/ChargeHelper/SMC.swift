import Foundation
import IOKit

/// 和电池控制芯片（AppleSMC）说话的最小实现：读键信息、读、写。
///
/// 结构体按 C 的 SMCKeyData_t 内存布局手工摆放（80 字节），不用 Swift
/// 结构体，免得 Swift 把字段塞进嵌套结构体的尾部填充、和内核对不上。
/// 写入要 root，所以只在助手里用。
final class SMC {
    private var connection: io_connect_t = 0

    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let data8 = 42
        static let bytes = 48
        static let total = 80
    }

    private enum Command: UInt8 {
        case read = 5
        case write = 6
        case keyInfo = 9
    }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// 发一条命令，返回 80 字节的回复；IOKit 出错或 SMC 报错时是 nil。
    private func call(_ key: String, _ command: Command, size: UInt32 = 0,
                      bytes: [UInt8] = []) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: Offset.total)
        var output = [UInt8](repeating: 0, count: Offset.total)
        put(Self.code(key), into: &input, at: Offset.key)
        put(size, into: &input, at: Offset.dataSize)
        input[Offset.data8] = command.rawValue
        for (i, b) in bytes.prefix(32).enumerated() { input[Offset.bytes + i] = b }
        var outSize = Offset.total
        let status = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, 2, inPtr.baseAddress, Offset.total,
                                          outPtr.baseAddress, &outSize)
            }
        }
        guard status == kIOReturnSuccess, output[Offset.result] == 0 else { return nil }
        return output
    }

    /// 键的大小；这台 Mac 没有这个键时是 nil。
    func size(of key: String) -> UInt32? {
        guard let out = call(key, .keyInfo) else { return nil }
        let size = get(out, at: Offset.dataSize)
        return size > 0 && size <= 32 ? size : nil
    }

    func read(_ key: String) -> [UInt8]? {
        guard let size = size(of: key), let out = call(key, .read, size: size) else { return nil }
        return Array(out[Offset.bytes..<(Offset.bytes + Int(size))])
    }

    @discardableResult
    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let size = size(of: key), Int(size) == bytes.count else { return false }
        return call(key, .write, size: size, bytes: bytes) != nil
    }

    private func put(_ value: UInt32, into buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { raw in
            for i in 0..<4 { buffer[offset + i] = raw[i] }
        }
    }

    private func get(_ buffer: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(buffer[offset + i]) << (8 * UInt32(i)) }
        return value
    }
}

/// 暂停或恢复充电。新固件（macOS 15 以后的 Apple 芯片）用 CHTE，旧固件
/// 用 CH0B 和 CH0C。都没有（比如 Intel Mac）就不支持。
struct ChargeSwitch {
    let smc: SMC
    let key: String

    init?(smc: SMC) {
        self.smc = smc
        if smc.size(of: "CHTE") == 4 {
            key = "CHTE"
        } else if smc.size(of: "CH0B") == 1, smc.size(of: "CH0C") == 1 {
            key = "CH0B"
        } else {
            return nil
        }
    }

    @discardableResult
    func set(inhibited: Bool) -> Bool {
        if key == "CHTE" {
            return smc.write("CHTE", inhibited ? [1, 0, 0, 0] : [0, 0, 0, 0])
        }
        let value: [UInt8] = [inhibited ? 0x02 : 0x00]
        let b = smc.write("CH0B", value)
        let c = smc.write("CH0C", value)
        return b && c
    }

    /// 芯片里现在是不是暂停着（助手重启后接着上次的状态判断）。
    var isInhibited: Bool? {
        guard let bytes = smc.read(key) else { return nil }
        return bytes.contains { $0 != 0 }
    }
}
