import AVFoundation
import Foundation
// Preconcurrency: `TranslationSession` is not Sendable, and calling its
// `translate` from the main actor, as Apple's own sample does from
// `.translationTask`, is otherwise rejected in the Swift 6 language mode.
@preconcurrency import Translation

/// One piece of text to translate, and which way.
struct TranslateJob: Equatable, Sendable {
    var text: String
    /// Nil: the framework works the language out itself.
    var source: String?
    var target: String

    var key: String { "\(source ?? Translate.auto)|\(target)|\(text)" }
}

enum TranslateOutcome: Equatable, Sendable {
    case done(TranslateRecord)
    /// Said in words: an unsupported pair, a missing language, a failure.
    case note(String)
    /// Superseded by a newer job; nothing to show.
    case cancelled
}

/// The translate widget's use of Apple's Translation framework.
///
/// On device, free and private: no key, and the text never leaves the Mac.
/// The framework only hands out a session through SwiftUI's
/// `.translationTask`, so the views own the session and this does the rest
/// with it: check the pair, translate, and turn the answer into a record.
@MainActor
enum TranslationRunner {
    static func configuration(for job: TranslateJob) -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: job.source.map { Locale.Language(identifier: $0) },
                                         target: Locale.Language(identifier: job.target))
    }

    /// Whether two configurations translate the same way, so the session can
    /// be asked again (`invalidate`) rather than replaced.
    static func samePair(_ a: TranslationSession.Configuration?, _ b: TranslationSession.Configuration) -> Bool {
        guard let a else { return false }
        return a.source == b.source && a.target == b.target
    }

    /// Our codes for every language this Mac can translate, or empty when
    /// the list could not be read (every common language is offered then).
    static func supportedCodes() async -> Set<String> {
        let languages = await LanguageAvailability().supportedLanguages
        return Set(languages.map { Translate.code(for: $0.maximalIdentifier) })
    }

    /// A language's name in Chinese, from our list or else the system's.
    static func name(_ code: String) -> String {
        if Translate.language(code) != nil || code == Translate.auto { return Translate.name(code) }
        return Locale(identifier: L10n.isEnglish ? "en" : "zh-Hans").localizedString(forIdentifier: code) ?? code
    }

    /// Translates one job with the session the view was given.
    ///
    /// `downloading` is called when the pair is supported but its language
    /// pack is not on this Mac yet: the framework asks to download it on its
    /// own, and the panel says why the answer is taking a moment.
    static func run(_ session: TranslationSession, job: TranslateJob,
                    downloading: () -> Void) async -> TranslateOutcome {
        if let source = job.source {
            let status = try? await LanguageAvailability().status(
                from: Locale.Language(identifier: source),
                to: Locale.Language(identifier: job.target))
            switch status {
            case .unsupported?:
                return .note(tr("暂不支持从\(name(source))翻译成\(name(job.target))。"))
            case .supported?:
                downloading()
            default:
                break
            }
        }
        do {
            let response = try await session.translate(job.text)
            let detected = Translate.code(for: response.sourceLanguage.maximalIdentifier)
            return .done(TranslateRecord(source: job.source ?? detected, target: job.target,
                                         sourceText: job.text, resultText: response.targetText))
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            let reason = error.localizedDescription
            if job.source == nil {
                return .note(tr("无法识别原文的语言，请在左上角选择源语言后再试。（\(reason)）"))
            }
            return .note(tr("翻译没有完成：\(reason)"))
        }
    }
}

/// 朗读: reads a side of the translation aloud in its own language.
@MainActor
final class TranslateSpeaker {
    static let shared = TranslateSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var spoken: String?

    private init() {}

    /// Reads the text, or stops if that same text is being read.
    func toggle(_ text: String, language: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            if spoken == text {
                spoken = nil
                return
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Translate.speechCode(language))
        synthesizer.speak(utterance)
        spoken = text
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        spoken = nil
    }
}
