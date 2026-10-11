import SwiftUI

/// How many messages in Mail's inbox are unread. The card opens Mail.
struct MailTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var mail: MailService { MailService.shared }

    private var state: MailState { context.isPreview ? .unread(3) : mail.state }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 4) {
                    badge(size: 34)
                    Text(shortLine)
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: 10) {
                    badge(size: 40)
                    TileReading(value: value, caption: caption)
                    Spacer(minLength: 0)
                    if state == .denied {
                        TileGlyph(symbol: "lock.fill", size: 10,
                                  action: { mail.openAutomationSettings() })
                            .help("打开“自动化”权限设置")
                    }
                }
            }
        }
        .onAppear { if !context.isPreview { mail.start() } }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: "envelope.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
        }
        .overlay(alignment: .topTrailing) {
            if case .unread(let count) = state, count > 0 {
                Text(MailBadge.figure(count))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 5, y: -5)
            }
        }
    }

    private var value: String {
        switch state {
        case .unread(let count): MailBadge.figure(count)
        case .notRunning: "邮件"
        case .denied, .failed: "-"
        }
    }

    private var caption: String {
        switch state {
        case .unread(let count): MailBadge.caption(count)
        case .notRunning: "未打开，点按打开"
        case .denied: "需要“自动化”权限"
        case .failed: "暂时无法读取"
        }
    }

    private var shortLine: String {
        switch state {
        case .unread(let count): count == 0 ? "无未读" : "\(MailBadge.figure(count)) 封未读"
        case .notRunning: "未打开"
        case .denied: "需要权限"
        case .failed: "无法读取"
        }
    }
}
