import AppKit
import SwiftUI

/// The record button at full size, and the recordings already made.
struct RecorderDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var recorder: VoiceRecorder { VoiceRecorder.shared }
    private var folderPath: String { instance.config.string("folder") }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.red))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "waveform", title: tr("录音"),
                            subtitle: context.isPreview ? tr("保存到“下载”") : tr("保存到“\(recorder.folder.lastPathComponent)”"))
                HStack(spacing: 8) {
                    PanelButton(title: recording ? tr("停止") : tr("开始录音"),
                                symbol: recording ? "stop.fill" : "mic.fill", prominent: true) {
                        guard !context.isPreview else { return }
                        recorder.toggle(folderPath: folderPath)
                    }
                    if recording, let started = recorder.startedAt {
                        Text(RecordingNaming.elapsed(context.now.timeIntervalSince(started)))
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(minWidth: 70)
                    }
                }
                if let error = recorder.error, !context.isPreview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error)
                            .font(WidgetStyle.caption(11))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                        PanelButton(title: tr("打开隐私设置"), symbol: "lock") { recorder.openPrivacySettings() }
                    }
                }
                list
                HStack(spacing: 8) {
                    PanelButton(title: tr("选择文件夹…"), symbol: "folder", action: choose)
                    PanelButton(title: tr("在访达中打开"), symbol: nil) {
                        guard !context.isPreview else { return }
                        FileActions.openFolder(recorder.folder)
                    }
                }
            }
        }
        .onAppear { if !context.isPreview { recorder.use(folderPath: folderPath) } }
    }

    private var recording: Bool { !context.isPreview && recorder.isRecording }

    @ViewBuilder
    private var list: some View {
        let items: [VoiceRecorder.Recording] = context.isPreview ? [] : recorder.recordings
        if items.isEmpty {
            PanelNote(symbol: "waveform",
                      text: tr("还没有录音。录音以 .m4a 格式保存，文件名以“录音”开头。"))
                .frame(height: 120)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in row(item) }
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(200, CGFloat(items.count) * 44))
        }
    }

    private func row(_ item: VoiceRecorder.Recording) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(RelativeAge.caption(item.date, now: context.now))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture { FileActions.open(item.url) }
        .onDrag { FileActions.dragProvider(item.url) }
        .contextMenu {
            Button("播放") { FileActions.open(item.url) }
            Button("在访达中显示") { FileActions.reveal([item.url]) }
            Divider()
            Button("移到废纸篓") { recorder.trash(item) }
        }
        .help("点按播放，拖移到其他地方即可使用")
    }

    private func choose() {
        guard !context.isPreview else { return }
        let item = instance
        guard let url = FileActions.chooseFolder(title: tr("选择录音的保存位置"), startingAt: recorder.folder) else { return }
        WidgetWriter.write(item) { $0.set("folder", .string(url.path)) }
        recorder.use(folderPath: url.path)
    }
}
