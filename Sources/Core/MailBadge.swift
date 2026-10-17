import Foundation

/// What the mail widget says about a count, kept pure for tests.
public enum MailBadge {
    /// Whatever Mail answered, as a count. AppleScript hands back a bare
    /// integer, but a descriptor's string value can carry stray spaces.
    public static func parse(_ text: String?) -> Int? {
        guard let text, let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 0 else { return nil }
        return value
    }

    /// The figure on the badge: "99+" past two digits, which is the point at
    /// which an exact number stops telling anyone anything.
    public static func figure(_ count: Int) -> String {
        count > 99 ? "99+" : "\(max(0, count))"
    }

    public static func caption(_ count: Int) -> String {
        count == 0 ? tr("没有未读邮件") : tr("封未读邮件")
    }
}
