import AppKit
import SwiftUI

/// 时间洞察 Pro：用户自定义规则。所有规则只在本机保存，不改写原始时长。
/// 标题规则需要另外同意窗口标题采集；域名规则需浏览器扩展接通后才能命中。
struct TimeInsightsRulesEditor: View {
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    @State private var kind: TimeInsightsRuleInput.Kind = .app
    @State private var pattern = ""
    @State private var category: TimeInsightsCategory = .development
    @State private var error: String?

    private var tracker: TimeInsightsTracker { .shared }
    private var unlocked: Bool { licenseUnlocked || supporter }

    var body: some View {
        Section {
            if tracker.settings.customRules.isEmpty {
                Text(tr("还没有自定义分类规则。未匹配的应用依然保持未分类。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(tracker.settings.customRules.enumerated()), id: \.offset) { index, rule in
                    HStack(spacing: 9) {
                        Image(systemName: rule.category.symbol)
                            .foregroundStyle(Color(hex: rule.category.colorHex))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ruleLabel(rule))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(rule.category.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if unlocked {
                            Button(tr("移除")) {
                                tracker.update { settings in
                                    guard settings.customRules.indices.contains(index) else { return }
                                    settings.customRules.remove(at: index)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if unlocked {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Picker(tr("匹配方式"), selection: $kind) {
                            Text(tr("应用")).tag(TimeInsightsRuleInput.Kind.app)
                            Text(tr("窗口标题")).tag(TimeInsightsRuleInput.Kind.title)
                            Text(tr("网站域名")).tag(TimeInsightsRuleInput.Kind.domain)
                        }
                        .frame(width: 185)

                        Picker(tr("分类"), selection: $category) {
                            ForEach(TimeInsightsCategory.allCases, id: \.rawValue) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(hint, text: $pattern)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addRule)
                        Button(tr("添加规则"), action: addRule)
                            .disabled(TimeInsightsRuleInput.make(kind: kind, text: pattern, category: category) == nil)
                    }

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    Text(kind == .domain
                         ? tr("网站域名规则会保存在本机，但浏览器扩展接通前不会自动识别网站。")
                         : (kind == .title
                            ? tr("标题规则只有在你单独开启窗口标题采集并授权辅助功能后才会匹配。")
                            : tr("按列表顺序优先匹配自定义规则，再使用内置分类。")))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text(tr("自定义分类规则属于码头 Pro，免费应用统计不受影响。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("了解 Pro…")) { PaywallWindow.shared.show() }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Label(tr("自定义分类规则"), systemImage: "slider.horizontal.3")
                ProBadge()
            }
        } footer: {
            Text(tr("规则只改变统计分类，不修改已记录的活动时长。编辑后日、周、月统计会重新按规则计算。"))
                .font(.system(size: 12))
        }
    }

    private var hint: String {
        switch kind {
        case .app: "com.example.app"
        case .title: tr("例如：设计稿")
        case .domain: "example.com"
        }
    }

    private func ruleLabel(_ rule: TimeInsightsRule) -> String {
        switch rule.match {
        case .bundleID(let value): return tr("应用") + " · " + value
        case .titleKeyword(let value): return tr("标题包含") + " · " + value
        case .domain(let value): return tr("网站域名") + " · " + value
        }
    }

    private func addRule() {
        guard unlocked,
              let rule = TimeInsightsRuleInput.make(kind: kind, text: pattern, category: category) else {
            error = tr("请输入有效的应用标识、关键词或域名。")
            return
        }
        if tracker.settings.customRules.contains(where: { $0.match == rule.match }) {
            error = tr("相同的匹配规则已经存在。")
            return
        }
        tracker.update { $0.customRules.insert(rule, at: 0) }
        pattern = ""
        error = nil
    }
}
