import AppKit

/// 看用户是不是正拖着东西（从访达拖文件等）。
///
/// 拖动会话一开始，系统往拖放剪贴板写内容，它的 changeCount 就变了。左键
/// 松开时记下当时的 changeCount；按着左键期间它变了，就是在拖。只读一个
/// 静态值和剪贴板计数，不需要任何权限，跟着扩展栏的 30Hz 轮询一起调用。
struct FileDragWatch {
    private var baseline = NSPasteboard(name: .drag).changeCount

    mutating func isActive() -> Bool {
        let count = NSPasteboard(name: .drag).changeCount
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            baseline = count
            return false
        }
        return count != baseline
    }
}
