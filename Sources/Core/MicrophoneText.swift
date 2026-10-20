import Foundation

/// What the microphone widget says, kept pure for tests.
public enum MicrophoneText {
    public static func value(inUse: Bool, muted: Bool) -> String {
        if muted { return tr("已静音") }
        return inUse ? tr("使用中") : tr("未使用")
    }

    public static func caption(deviceName: String) -> String {
        deviceName.isEmpty ? tr("没有输入设备") : deviceName
    }

    /// 卡片第二行：有 App 在用时写谁在用（多个写「等 N 个」），没有时写设备名。
    public static func caption(deviceName: String, apps: [String]) -> String {
        guard let first = apps.first else { return caption(deviceName: deviceName) }
        return apps.count == 1 ? first : tr("\(first) 等 \(apps.count) 个")
    }
}
