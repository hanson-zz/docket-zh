import SwiftUI

/// One button that starts and stops a voice memo, and how long it has run.
///
/// The button takes the click only where it sits; the rest of the card opens
/// the panel with the recent recordings.
struct RecorderTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var recorder: VoiceRecorder { VoiceRecorder.shared }
    private var folderPath: String { instance.config.string("folder") }

    private var recording: Bool { context.isPreview ? false : recorder.isRecording }

    private var reading: String {
        if context.isPreview { return "0:00" }
        guard let started = recorder.startedAt else { return tr("录音") }
        return RecordingNaming.elapsed(context.now.timeIntervalSince(started))
    }

    private var caption: String {
        if context.isPreview { return tr("点按开始录音") }
        if recorder.error != nil { return tr("没有麦克风权限") }
        if recording { return tr("正在录音…") }
        if let last = recorder.recordings.first {
            return tr("上次 \(RelativeAge.caption(last.date, now: context.now))")
        }
        return tr("保存到“\(recorder.folder.lastPathComponent)”")
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) {
                    button(size: 14)
                    Text(reading)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: 10) {
                    button(size: 14)
                    TileReading(value: reading, caption: caption, valueSize: 17)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { if !context.isPreview { recorder.use(folderPath: folderPath) } }
    }

    private func button(size: CGFloat) -> some View {
        TileGlyph(symbol: recording ? "stop.fill" : "mic.fill", size: size,
                  tint: recording || context.isPreview ? .red : WidgetStyle.primary,
                  action: context.isPreview ? nil : { recorder.toggle(folderPath: folderPath) })
            .help(recording ? tr("停止录音") : tr("开始录音"))
            .accessibilityLabel(recording ? tr("停止录音") : tr("开始录音"))
    }
}
