import Foundation
import SwiftUI

/// The ways to chip in: WeChat and Alipay for people in China, Ko-fi
/// (PayPal or card) for everyone else.
enum SponsorMethod: Int, CaseIterable, Identifiable {
    case wechat, alipay, kofi
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wechat: tr("微信")
        case .alipay: tr("支付宝")
        case .kofi: "Ko-fi"
        }
    }

    var hint: String {
        switch self {
        case .wechat: tr("微信支付，适合国内用户")
        case .alipay: tr("支付宝，适合国内用户")
        case .kofi: tr("Ko-fi，支持 PayPal 和信用卡，适合海外用户")
        }
    }

    var symbol: String {
        switch self {
        case .wechat: "message.fill"
        case .alipay: "yensign.circle.fill"
        case .kofi: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .wechat: Color(red: 0.03, green: 0.76, blue: 0.38)
        case .alipay: Color(red: 0.09, green: 0.47, blue: 1.0)
        case .kofi: Color(red: 0.16, green: 0.67, blue: 0.88)
        }
    }

    var imageName: String {
        switch self {
        case .wechat: "SponsorWeChat"
        case .alipay: "SponsorAlipay"
        case .kofi: "SponsorKofi"
        }
    }

    /// WeChat for a Chinese system or a China region, Ko-fi otherwise.
    static func pick(languages: [String], region: String?) -> SponsorMethod {
        let chinese = languages.first?.hasPrefix("zh") ?? false
        return chinese || region == "CN" ? .wechat : .kofi
    }

    static var preferred: SponsorMethod {
        pick(languages: Locale.preferredLanguages, region: Locale.current.region?.identifier)
    }
}
