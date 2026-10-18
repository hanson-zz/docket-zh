import AppKit
import EventKit

/// 快速待办右键“转成提醒事项”：在系统提醒事项里建一条，成功后由面板把它从
/// 快速待办里拿掉。
///
/// 快速待办本身不要任何权限；只有在这里、用户点了“转成提醒事项”时才请求
/// 提醒事项权限，卡片和面板打开时都不会弹授权框。
@MainActor
enum TodoReminderExport {
    enum Outcome: Equatable {
        case saved
        /// 没给权限，或者在系统设置里关掉了。
        case denied
        case failed(String)
    }

    /// 写入用的那个，建一次就一直用。
    private static let store = EKEventStore()

    /// - Parameter due: 提醒的日期（只记年月日，全天）。nil 时不设日期。
    static func export(_ item: TodoItem, due: Date?) async -> Outcome {
        var status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            // 和提醒事项面板一样另建一个去请求：请求是一次跨出主线程的异步调用。
            _ = try? await EKEventStore().requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
            // 授权之前建好的 store 要重新看一次，不然还当作没有权限。
            store.reset()
        }
        guard status == .fullAccess else { return .denied }
        guard let list = store.defaultCalendarForNewReminders() else {
            return .failed(tr("没有可以写入的提醒事项列表"))
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = item.text
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        }
        if let url = item.url {
            reminder.url = url
            reminder.notes = url.isFileURL ? url.path : url.absoluteString
        }
        do {
            try store.save(reminder, commit: true)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 系统设置 ▸ 隐私与安全性 ▸ 提醒事项。
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
