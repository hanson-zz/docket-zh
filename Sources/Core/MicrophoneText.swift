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
}
