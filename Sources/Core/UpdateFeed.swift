import Foundation

/// 检查新版本时去问哪个 GitHub 仓库的 Releases。
///
/// 仓库名不写死在代码里，而是在构建时写进 Info.plist 的
/// `DocklingUpdateRepository`（来自 project.yml 的构建设置
/// `DOCKLING_UPDATE_REPOSITORY`，发布构建时由 release.yml 按仓库变量
/// `UPDATE_FEED_REPOSITORY` 覆盖）。这样以后把安装包搬到单独的发布仓库，
/// 只要改一个变量重新打包，不用改代码。
///
/// 读不到、读到的是没替换的构建变量，或者不像 `owner/repo` 的值时，退回
/// `fallback`，也就是现在一直在用的仓库，保证已有用户的更新检查不会因为
/// 配置写错而失效。
public enum UpdateFeed {
    /// 现在一直在用的仓库。改动更新源请改构建设置，不要改这里。
    public static let fallback = "hanson-zz/docket-zh"

    /// Info.plist 里的键名。
    public static let infoKey = "DocklingUpdateRepository"

    /// 从 Info.plist 的原始值得出要用的仓库。
    public static func repository(from raw: Any?) -> String {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValid(text) else { return fallback }
        return text
    }

    /// `owner/repo`：两段都只含 GitHub 允许的字母、数字、`-`、`_`、`.`，
    /// 不能是空的，也不能带构建变量 `$(...)` 这类没替换掉的内容。
    public static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".."
                && part.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
        }
    }
}
