import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 读、切键盘输入法：系统的 Text Input Sources 接口（Carbon 里的 TIS）。不需要任何权限。
///
/// 只列能选中的键盘输入法（键盘布局、输入法的模式、没有模式的输入法），去掉表情与符号这类
/// 面板，见 `InputSourceCatalog.selectable`。判断都在 Core 的 `InputSourceResolver`。
@MainActor
enum InputSourceService {
    /// 系统输入法菜单里那些，按系统给的顺序。
    static func available() -> [InputSourceInfo] {
        InputSourceCatalog.selectable(raw().map(\.info))
    }

    /// 现在用的键盘输入法的 id。
    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    /// 切到这个输入法。找不到或系统拒绝时返回 false。
    @discardableResult
    static func select(_ id: String) -> Bool {
        guard let source = raw().first(where: { $0.info.id == id && $0.info.selectable })?.source else { return false }
        return TISSelectInputSource(source) == noErr
    }

    /// 输入法自己的图标（有的输入法只给图片地址），拿不到时 nil，界面画字形徽章。
    static func icon(_ id: String) -> NSImage? {
        guard let source = raw().first(where: { $0.info.id == id })?.source else { return nil }
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
            return NSImage(contentsOf: url)
        }
        return nil
    }

    // MARK: 读

    private struct Raw {
        var source: TISInputSource
        var info: InputSourceInfo
    }

    private static func raw() -> [Raw] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
            let info = InputSourceInfo(
                id: id,
                name: string(source, kTISPropertyLocalizedName) ?? id,
                languages: strings(source, kTISPropertyInputSourceLanguages),
                type: string(source, kTISPropertyInputSourceType) ?? "",
                selectable: bool(source, kTISPropertyInputSourceIsSelectCapable),
                enabled: bool(source, kTISPropertyInputSourceIsEnabled))
            return Raw(source: source, info: info)
        }
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func strings(_ source: TISInputSource, _ key: CFString) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    // MARK: 变化

    /// 用户在系统设置里加减输入法、手动切了输入法时系统发的分布式通知。
    static let changeNotifications: [Notification.Name] = [
        Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
        Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    ]
}

/// 光标旁的提示：用辅助功能读前台 App 焦点元素的插入点位置。没权限、App 不支持、
/// 没有插入点时都是 nil，提示临时改用刘海下。不隔离到主线程：每个元素都设超时，App 卡住
/// 时最多等 `timeout` 秒，放在后台读。
enum InputSourceCaret {
    static let timeout: Float = 0.25

    /// 插入点在屏幕上的位置，AppKit 坐标（左下原点）。`primaryHeight` 是主屏高度。
    static func rect(pid: pid_t, primaryHeight: CGFloat) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let raw = AXWindowReader.copy(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let rangeValue = AXWindowReader.copy(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        // 插入点（没有选中文字）时取它前面一个字的范围，有的 App 对长度 0 的范围不给位置。
        var probe = CFRange(location: range.location, length: max(range.length, 0))
        var bounds = self.bounds(element, probe)
        if bounds == nil || bounds?.height == 0, range.length == 0, range.location > 0 {
            probe = CFRange(location: range.location - 1, length: 1)
            if let previous = self.bounds(element, probe) {
                bounds = CGRect(x: previous.maxX, y: previous.minY, width: 1, height: previous.height)
            }
        }
        guard let topLeft = bounds, topLeft.height > 0, topLeft.height < 400 else { return nil }
        return NotchWindowGeometry.appKit(topLeft, primaryHeight: primaryHeight)
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}
