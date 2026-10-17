import AppKit
import SwiftUI

/// 设置 ▸ 通用 最下面的“许可”一节：开源致谢和最终用户协议各开一个窗口。
struct LicenseSection: View {
    var body: some View {
        Section {
            Button("开源致谢与许可…") { CreditsWindow.shared.show() }
                .buttonStyle(.link)
            Button("最终用户许可协议…") { EULAWindow.shared.show() }
                .buttonStyle(.link)
        } header: {
            Text("许可")
        } footer: {
            Text("码头基于 Naman Parashar 的开源项目 Docket（MIT 许可）开发。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 版权声明和许可原文。许可原文照抄英文，不翻译：翻译件没有法律效力。
struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("开源致谢与许可")
                    .font(.title2.weight(.bold))
                Text(Licensing.ownNotice)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Licensing.credits) { credit in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(credit.project).font(.headline)
                            Spacer()
                            if let url = URL(string: credit.link) {
                                Link(credit.link, destination: url)
                                    .font(.caption)
                            }
                        }
                        Text(credit.usage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        LicenseText(text: credit.text)
                    }
                }
                Text(Licensing.dataSources)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

/// 最终用户许可协议全文。
struct EULAView: View {
    var body: some View {
        ScrollView {
            Text(Licensing.eula)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

/// 一段许可原文：等宽小字，放在浅色底上，可以选中拷贝。
private struct LicenseText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
    }
}

@MainActor
final class CreditsWindow: HostedWindow {
    static let shared = CreditsWindow()

    func show() {
        present(CreditsView(), title: tr("开源致谢与许可"),
                size: NSSize(width: 620, height: 560), resizable: true)
    }
}

@MainActor
final class EULAWindow: HostedWindow {
    static let shared = EULAWindow()

    func show() {
        present(EULAView(), title: tr("最终用户许可协议"),
                size: NSSize(width: 560, height: 560), resizable: true)
    }
}
