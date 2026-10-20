import AppKit
import SwiftUI

/// 录音面板：大录音钮、按天分组的录音列表，面板里直接播放和编辑。
///
/// 两个状态：
/// - 浏览：顶上大录音钮（录完自动转文字，Pro）。展开的那一条有播放钮、可拖动
///   的波形、转写文字和“复制文字 / 改名 / 裁剪”；其余收起成一行，写一行文字
///   预览或时间；正在转文字的那条写进度。右键照旧能用默认 App 打开、在访达中
///   显示、移到废纸篓，也能直接拖走。
/// - 编辑（Pro）：右上“编辑”或“裁剪”进入。改名、拖两端裁剪、试听选段、逐段改
///   文字，“存为新录音”把选段另存一条，原来那条不动；“删除这条录音”移到废纸篓。
///
/// 免费和 Pro（用户 2026-10-20 定）：录音整种免费，录、听、拖动进度、改名、删除
/// 和列表都免费；转文字、裁剪和编辑是 Pro（`ProLicenseGate.canUseRecorderTools`）。
/// 没解锁时这几个钮带 Pro 标，点了弹付费墙，不盖锁、不改配置，已有的文字照旧存着。
struct RecorderDetail: View {
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, edit }
    private enum Field: Hashable { case rename, title }

    @State private var mode: Mode = .browse
    /// 浏览态展开的那一条；nil 时展开最新的一条。
    @State private var expanded: URL?
    /// 浏览态正在改名的那一条和输入的字。
    @State private var renaming: URL?
    @State private var renameText = ""
    /// 拖波形时的位置（0 到 1），松手前先画在这里。
    @State private var scrub: Double?
    /// 拖完或跳完后让暂停着的进度重画一次。
    @State private var redraw = 0
    // 编辑态
    @State private var editing: URL?
    @State private var draftTitle = ""
    @State private var draftSegments: [TranscriptSegment]?
    @State private var trim = RecordingTrim(duration: 0)
    @State private var confirmDone = false
    @State private var saving = false
    @FocusState private var focus: Field?

    private static let accentHex = "#FF7B6E"
    private static let inkHex = "#330B05"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }
    private static let red = Color(red: 1, green: 0.42, blue: 0.35)

    private var recorder: VoiceRecorder { VoiceRecorder.shared }
    private var transcriber: RecordingTranscriber { RecordingTranscriber.shared }
    private var folderPath: String { instance.config.string("folder") }
    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }
    private var tools: Bool { ProLicenseGate.canUseRecorderTools(unlocked: unlocked) }
    private var recording: Bool { !context.isPreview && recorder.isRecording }
    private var items: [VoiceRecorder.Recording] { context.isPreview ? [] : recorder.recordings }
    private var folderName: String {
        context.isPreview ? tr("下载") : recorder.folder.lastPathComponent
    }

    /// 编辑态的那一条；文件不在了（访达里删掉）或 Pro 到期时退回浏览。
    private var editingRecording: VoiceRecorder.Recording? {
        guard mode == .edit, tools, let editing else { return nil }
        return items.first { $0.url == editing }
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.red))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let item = editingRecording {
                    editView(item)
                } else {
                    browse
                }
            }
            .onChange(of: focus) { old, new in
                if old == .rename, new != .rename { commitRename() }
            }
            // 编辑着的录音在访达里被删掉、或 Pro 到期：回到浏览，下次不会误回编辑态。
            .onChange(of: editingRecording == nil) { _, gone in
                if gone, mode == .edit { leaveEdit(showing: nil) }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            recorder.use(folderPath: folderPath)
            recorder.clearNotice()
        }
        .onDisappear {
            // 面板关了就不再响；试听也停。
            if !context.isPreview { recorder.stopPlayback() }
        }
        .confirmationDialog(tr("裁剪还没保存"), isPresented: $confirmDone) {
            Button(tr("存为新录音")) { if let item = editingRecording { saveAsNew(item) } }
            Button(tr("不保存裁剪")) { if let item = editingRecording { finishEdit(item) } }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("裁剪只会存成一条新录音，原来那条不动。"))
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private var browse: some View {
        browseHeader
        recordCard
        if let error = recorder.error, !context.isPreview {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                pill(tr("打开隐私设置")) { recorder.openPrivacySettings() }
            }
        }
        noticeLine
        list
        HStack(spacing: 8) {
            pill(tr("选择文件夹…"), action: choose)
            pill(tr("在访达中打开")) {
                guard !context.isPreview else { return }
                FileActions.openFolder(recorder.folder)
            }
        }
    }

    private var browseHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("录音"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                HStack(spacing: 5) {
                    if tools {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(tr("本机转文字，不联网"))
                    } else {
                        Text(tr("转文字、裁剪和编辑"))
                        ProBadge()
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !context.isPreview, !items.isEmpty {
                Button { startEdit(shownExpanded ?? items[0]) } label: {
                    HStack(spacing: 5) {
                        Text(tr("编辑"))
                        if !tools { ProBadge() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(tools && isBusy((shownExpanded ?? items[0]).url))
                .help(tr("改名、裁剪、改文字"))
            }
        }
    }

    private var recordCard: some View {
        Button {
            guard !context.isPreview else { return }
            if !recorder.isRecording { recorder.stopPlayback() }
            recorder.toggle(folderPath: folderPath)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(accent).frame(width: 48, height: 48)
                    if recording {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accentInk).frame(width: 16, height: 16)
                    } else {
                        Circle().fill(accentInk).frame(width: 18, height: 18)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording ? tr("停止录音") : tr("开始录音"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(recordCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if recording, let started = recorder.startedAt {
                    Text(RecorderClock.text(context.now.timeIntervalSince(started)))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 72)
            .glassPane(cornerRadius: 16)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? tr("停止录音") : tr("开始录音"))
    }

    private var recordCaption: String {
        if recording { return tr("正在录音…") }
        return tools ? tr("存到「\(folderName)」 · 录完自动转文字") : tr("存到「\(folderName)」")
    }

    @ViewBuilder
    private var noticeLine: some View {
        if let notice = recorder.notice, !context.isPreview {
            Text(notice)
                .font(.system(size: 13))
                .foregroundStyle(Self.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 展开的那一条：点过的那条，没点过（或它已经不在了）是最新的一条。
    private var shownExpanded: VoiceRecorder.Recording? {
        if let expanded, let hit = items.first(where: { $0.url == expanded }) { return hit }
        return items.first
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            HStack(spacing: 12) {
                if let image = PandaArt.image("pet-panda-idle") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 56)
                        .accessibilityHidden(true)
                }
                Text(tr("还没有录音。录音以 .m4a 格式保存，文件名以“录音”开头。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .glassPane(cornerRadius: 14)
        } else {
            let open = shownExpanded?.url
            ForEach(RecorderDay.groups(items, date: \.date, now: context.now), id: \.day) { group in
                Text(RecorderDay.header(group.day, count: group.items.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 2)
                VStack(spacing: 8) {
                    ForEach(group.items) { item in
                        Group {
                            if item.url == open {
                                expandedRow(item)
                            } else if tools, isBusy(item.url) {
                                transcribingRow(item)
                            } else {
                                collapsedRow(item)
                            }
                        }
                        .onAppear { recorder.analyzeIfNeeded(item.url) }
                        .contextMenu { menu(item) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(_ item: VoiceRecorder.Recording) -> some View {
        Button(tr("用默认 App 打开")) { FileActions.open(item.url) }
        Button(tr("在访达中显示")) { FileActions.reveal([item.url]) }
        Divider()
        Button(tr("移到废纸篓")) { trash(item) }
    }

    // MARK: 展开的一条

    private func expandedRow(_ item: VoiceRecorder.Recording) -> some View {
        let segments = recorder.segments(for: item.url)
        let hasText = tools && Transcript.hasText(segments ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if renaming == item.url {
                        renameField(item)
                    } else {
                        Text(verbatim: RecorderTitle.display(fileName: item.url.lastPathComponent))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(RecorderClock.caption(date: item.date, duration: item.duration, now: context.now))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                playButton(item, size: 34, solid: true)
            }
            // 拖标题这一块把文件拖走；波形上拖是调进度，不能拖走文件。
            .contentShape(.rect)
            .onDrag { FileActions.dragProvider(item.url) }
            playback(item)
            transcriptBox(item, segments: segments)
            HStack(spacing: 6) {
                firstAction(item, segments: segments, hasText: hasText)
                pill(tr("改名"), height: 26) { startRename(item) }
                    .disabled(isBusy(item.url))
                pill(tr("裁剪"), height: 26, pro: !tools) { startEdit(item) }
                    .disabled(tools && isBusy(item.url))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
                }
        }
    }

    /// 波形和两头的时间。播着时每帧重画，暂停时不动。
    private func playback(_ item: VoiceRecorder.Recording) -> some View {
        let active = recorder.playingURL == item.url
        let live = active && recorder.isPlaying && scrub == nil
        return TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !live)) { _ in
            let _ = redraw
            let duration = item.duration ?? recorder.analyses[item.url]?.duration ?? 0
            let now = active ? recorder.currentTime : 0
            let fraction = scrub ?? (duration > 0 ? now / duration : 0)
            VStack(spacing: 6) {
                GeometryReader { geo in
                    WaveformBarsView(bars: recorder.analyses[item.url]?.bars ?? Waveform.bars([]),
                                     progress: fraction, trim: nil, accent: accent)
                        .contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    scrub = Waveform.fraction(x: value.location.x, width: geo.size.width)
                                }
                                .onEnded { value in
                                    let f = Waveform.fraction(x: value.location.x, width: geo.size.width)
                                    recorder.seek(item.url, fraction: f)
                                    scrub = nil
                                    redraw += 1
                                })
                }
                .frame(height: 34)
                .accessibilityLabel(tr("播放进度"))
                .accessibilityValue(RecorderClock.text(fraction * duration))
                HStack {
                    Text(RecorderClock.text(fraction * duration))
                        .foregroundStyle(.white.opacity(0.86))
                    Spacer(minLength: 0)
                    Text(RecorderClock.text(duration))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func transcriptBox(_ item: VoiceRecorder.Recording, segments: [TranscriptSegment]?) -> some View {
        if !tools {
            EmptyView()
        } else if let status = transcriber.status(item.url) {
            boxed {
                switch status {
                case .queued:
                    progressLine(tr("排队转文字…"), fraction: nil)
                case .running(let p):
                    progressLine(p > 0 ? tr("正在转文字 \(Int(p * 100))%") : tr("正在转文字…"), fraction: p)
                case .unavailable:
                    statusLine(tr("无法转写"), detail: tr("这台 Mac 不支持本机语音识别"))
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        statusLine(tr("无法转写"), detail: tr("没有语音识别权限"))
                        pill(tr("打开隐私设置"), height: 26) { transcriber.openPrivacySettings() }
                    }
                case .failed(let reason):
                    statusLine(tr("转写失败"), detail: reason)
                }
            }
        } else if let segments {
            boxed {
                if Transcript.hasText(segments) {
                    Text(verbatim: Transcript.preview(segments))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    statusLine(tr("没有识别到说话"), detail: nil)
                }
            }
        } else if !transcriber.supportsOnDevice {
            boxed { statusLine(tr("无法转写"), detail: tr("这台 Mac 不支持本机语音识别")) }
        }
    }

    @ViewBuilder
    private func firstAction(_ item: VoiceRecorder.Recording, segments: [TranscriptSegment]?, hasText: Bool) -> some View {
        if !tools {
            pill(tr("转文字"), height: 26, pro: true) { PaywallWindow.shared.show() }
        } else if hasText {
            pill(tr("复制文字"), height: 26, solid: true) { copy(Transcript.fullText(segments ?? [])) }
        } else {
            pill(segments == nil ? tr("转文字") : tr("重新转"), height: 26, solid: true) {
                transcriber.transcribe(item.url)
            }
            .disabled(isBusy(item.url) || !transcriber.supportsOnDevice)
        }
    }

    private func boxed<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
    }

    private func statusLine(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if let detail {
                Text(verbatim: detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressLine(_ title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .monospacedDigit()
            progressBar(fraction ?? 0)
        }
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(accent).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 5)
    }

    private func renameField(_ item: VoiceRecorder.Recording) -> some View {
        TextField(RecorderTitle.display(fileName: item.url.lastPathComponent), text: $renameText)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .focused($focus, equals: .rename)
            .onSubmit { commitRename() }
            .onExitCommand { renaming = nil }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(0.9), lineWidth: 1.2))
    }

    // MARK: 收起的一条、转文字中的一条

    private func collapsedRow(_ item: VoiceRecorder.Recording) -> some View {
        let segments = tools ? recorder.segments(for: item.url) : nil
        let preview = Transcript.preview(segments ?? [])
        return HStack(spacing: 12) {
            playButton(item, size: 30, solid: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: RecorderTitle.display(fileName: item.url.lastPathComponent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: preview.isEmpty
                     ? RecorderClock.caption(date: item.date, duration: nil, now: context.now)
                     : preview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let duration = item.duration {
                Text(RecorderClock.text(duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(rowBackground)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { expand(item) }
        .onDrag { FileActions.dragProvider(item.url) }
        .help(tr("点按展开，拖移到其他地方即可使用"))
    }

    private func transcribingRow(_ item: VoiceRecorder.Recording) -> some View {
        let status = transcriber.status(item.url)
        var fraction: Double = 0
        if case .running(let p) = status { fraction = p }
        let label = status == .queued ? tr("排队转文字…")
            : fraction > 0 ? tr("正在转文字 \(Int(fraction * 100))%") : tr("正在转文字…")
        return HStack(spacing: 8) {
            if let image = PandaArt.image("pet-panda-sip") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 58)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: RecorderTitle.display(fileName: item.url.lastPathComponent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                progressBar(fraction)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 70)
        .background(rowBackground)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { expand(item) }
        .onDrag { FileActions.dragProvider(item.url) }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
            }
    }

    private func playButton(_ item: VoiceRecorder.Recording, size: CGFloat, solid: Bool) -> some View {
        let playing = recorder.playingURL == item.url && recorder.isPlaying
        return Button {
            guard !context.isPreview, !recorder.isRecording else { NSSound.beep(); return }
            expand(item)
            recorder.togglePlay(item.url)
        } label: {
            ZStack {
                Circle().fill(solid ? accent : .white)
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(solid ? accentInk : Color(hex: "#1d1d21"))
                    .offset(x: playing ? 0 : size * 0.04)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playing ? tr("暂停") : tr("播放"))
        .accessibilityLabel(playing ? tr("暂停") : tr("播放"))
    }

    // MARK: 编辑

    @ViewBuilder
    private func editView(_ item: VoiceRecorder.Recording) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("编辑录音"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(tr("改名 · 裁剪 · 改文字"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button { tapDone(item) } label: {
                Text(tr("完成"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 15)
                    .frame(height: 28)
                    .background(Capsule().fill(accent))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        titleField(item)
        sectionLabel(tr("裁剪"), right: tr("拖两端"))
        trimBox(item)
        HStack(spacing: 8) {
            pill(tr("试听选段"), height: 32) {
                recorder.playRange(item.url, start: trim.start, end: trim.end)
            }
            pill(tr("还原"), height: 32) { trim.reset() }
                .disabled(trim.isFull)
        }
        sectionLabel(tr("文字"), right: tr("点进去直接改"))
            .padding(.top, 6)
        textBox(item)
        HStack(spacing: 8) {
            pill(tr("复制全部文字"), height: 36) { copy(Transcript.fullText(currentSegments(item))) }
                .disabled(!Transcript.hasText(currentSegments(item)))
            pill(saving ? tr("正在保存…") : tr("存为新录音"), height: 36, solid: true) { saveAsNew(item) }
                .disabled(saving || trim.duration <= 0)
        }
        noticeLine
        Button { deleteEditing(item) } label: {
            Text(tr("删除这条录音"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.red)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(saving)
    }

    private func titleField(_ item: VoiceRecorder.Recording) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            TextField(RecorderTitle.display(fileName: item.url.lastPathComponent), text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .focused($focus, equals: .title)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(focus == .title ? accent.opacity(0.9) : .white.opacity(0.14), lineWidth: focus == .title ? 1.2 : 0.6))
    }

    private func sectionLabel(_ title: String, right: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            Text(right)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
    }

    private func trimBox(_ item: VoiceRecorder.Recording) -> some View {
        let bars = recorder.analyses[item.url]?.bars ?? Waveform.bars([])
        return VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let x0 = w * trim.startFraction
                let x1 = w * trim.endFraction
                ZStack(alignment: .topLeading) {
                    WaveformBarsView(bars: bars, progress: nil,
                                     trim: (trim.startFraction, trim.endFraction), accent: accent)
                        .padding(.vertical, 6)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(accent.opacity(0.9), lineWidth: 1.6)
                        .frame(width: max(8, x1 - x0), height: 60)
                        .offset(x: x0, y: 2)
                        .allowsHitTesting(false)
                    handle
                        .offset(x: x0 - 4)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { v in
                            trim.setStart(fraction: Waveform.fraction(x: v.location.x, width: w))
                        })
                        .accessibilityLabel(tr("选段开头"))
                    handle
                        .offset(x: x1 - 4)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { v in
                            trim.setEnd(fraction: Waveform.fraction(x: v.location.x, width: w))
                        })
                        .accessibilityLabel(tr("选段结尾"))
                }
                .coordinateSpace(.named("trim"))
            }
            .frame(height: 64)
            HStack {
                Text(trim.rangeLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(trim.remainingLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
        .onAppear { syncTrim(item) }
        .onChange(of: item.duration) { syncTrim(item) }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(accent)
            .frame(width: 8, height: 64)
            .contentShape(Rectangle().inset(by: -8))
            .pointerStyle(.columnResize)
    }

    @ViewBuilder
    private func textBox(_ item: VoiceRecorder.Recording) -> some View {
        let segments = currentSegments(item)
        VStack(alignment: .leading, spacing: 10) {
            if let status = transcriber.status(item.url), transcriber.isBusy(item.url) {
                if case .running(let p) = status, p > 0 {
                    progressLine(tr("正在转文字 \(Int(p * 100))%"), fraction: p)
                } else {
                    progressLine(tr("正在转文字…"), fraction: nil)
                }
            } else if segments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if case .failed(let reason) = transcriber.status(item.url) {
                        statusLine(tr("转写失败"), detail: reason)
                    } else if !transcriber.supportsOnDevice || transcriber.status(item.url) == .unavailable {
                        statusLine(tr("无法转写"), detail: tr("这台 Mac 不支持本机语音识别"))
                    } else {
                        statusLine(recorder.segments(for: item.url) == nil ? tr("还没有文字") : tr("没有识别到说话"),
                                   detail: nil)
                    }
                    if transcriber.supportsOnDevice {
                        pill(tr("转文字"), height: 28, solid: true) {
                            draftSegments = nil
                            transcriber.transcribe(item.url)
                        }
                    }
                }
            } else {
                ForEach(segments.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(RecorderClock.text(segments[index].start))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 46, alignment: .leading)
                        TextField("", text: segmentBinding(item, index), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1...8)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(0.6), lineWidth: 1))
    }

    private func currentSegments(_ item: VoiceRecorder.Recording) -> [TranscriptSegment] {
        draftSegments ?? recorder.segments(for: item.url) ?? []
    }

    private func segmentBinding(_ item: VoiceRecorder.Recording, _ index: Int) -> Binding<String> {
        Binding {
            let list = currentSegments(item)
            return list.indices.contains(index) ? list[index].text : ""
        } set: { text in
            var list = currentSegments(item)
            guard list.indices.contains(index) else { return }
            list[index].text = text
            draftSegments = list
        }
    }

    // MARK: 动作

    private func isBusy(_ url: URL) -> Bool { transcriber.isBusy(url) }

    private func expand(_ item: VoiceRecorder.Recording) {
        if renaming != nil, renaming != item.url { commitRename() }
        withAnimation(.snappy(duration: 0.25)) { expanded = item.url }
    }

    private func startRename(_ item: VoiceRecorder.Recording) {
        guard !context.isPreview, !isBusy(item.url) else { return }
        renameText = RecorderTitle.editable(fileName: item.url.lastPathComponent)
        renaming = item.url
        WidgetDetailWindow.shared.focusField { focus = .rename }
    }

    private func commitRename() {
        guard let url = renaming else { return }
        renaming = nil
        guard let item = items.first(where: { $0.url == url }), !isBusy(url) else { return }
        if let renamed = recorder.rename(item, to: renameText) { expanded = renamed }
    }

    private func startEdit(_ item: VoiceRecorder.Recording) {
        guard !context.isPreview else { return }
        guard tools else {
            PaywallWindow.shared.show()
            return
        }
        guard !isBusy(item.url) else { return }
        commitRename()
        recorder.stopPlayback()
        recorder.clearNotice()
        recorder.analyzeIfNeeded(item.url)
        draftTitle = RecorderTitle.editable(fileName: item.url.lastPathComponent)
        draftSegments = nil
        trim = RecordingTrim(duration: item.duration ?? recorder.analyses[item.url]?.duration ?? 0)
        editing = item.url
        withAnimation(.snappy(duration: 0.25)) { mode = .edit }
    }

    /// 时长是后读出来的：还没拖过时跟着换成整条。
    private func syncTrim(_ item: VoiceRecorder.Recording) {
        let duration = item.duration ?? recorder.analyses[item.url]?.duration ?? 0
        if trim.duration != duration, trim.isFull || trim.duration == 0 {
            trim = RecordingTrim(duration: duration)
        }
    }

    private func tapDone(_ item: VoiceRecorder.Recording) {
        if !trim.isFull { confirmDone = true } else { finishEdit(item) }
    }

    /// 存名字和改过的文字，回到浏览。
    private func finishEdit(_ item: VoiceRecorder.Recording) {
        recorder.stopPlayback()
        if let draft = draftSegments, draft != recorder.segments(for: item.url) {
            recorder.setSegments(draft, for: item.url)
        }
        var shown = item.url
        if RecorderTitle.clean(draftTitle) != nil, let renamed = recorder.rename(item, to: draftTitle) {
            shown = renamed
        }
        leaveEdit(showing: shown)
    }

    private func saveAsNew(_ item: VoiceRecorder.Recording) {
        guard !saving else { return }
        saving = true
        recorder.stopPlayback()
        let title = draftTitle.isEmpty ? RecorderTitle.display(fileName: item.url.lastPathComponent) : draftTitle
        let segments = currentSegments(item)
        let range = trim
        Task {
            let made = await recorder.saveExcerpt(of: item, title: title, trim: range, segments: segments)
            saving = false
            if let made { leaveEdit(showing: made) }
        }
    }

    private func deleteEditing(_ item: VoiceRecorder.Recording) {
        trash(item)
        leaveEdit(showing: nil)
    }

    private func trash(_ item: VoiceRecorder.Recording) {
        if renaming == item.url { renaming = nil }
        recorder.trash(item)
        if expanded == item.url { expanded = nil }
    }

    private func leaveEdit(showing url: URL?) {
        withAnimation(.snappy(duration: 0.25)) {
            mode = .browse
            editing = nil
            draftSegments = nil
            draftTitle = ""
            expanded = url
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func choose() {
        guard !context.isPreview else { return }
        let item = instance
        guard let url = FileActions.chooseFolder(title: tr("选择录音的保存位置"), startingAt: recorder.folder) else { return }
        WidgetWriter.write(item) { $0.set("folder", .string(url.path)) }
        recorder.stopPlayback()
        recorder.use(folderPath: url.path)
        expanded = nil
    }

    // MARK: 小零件

    /// 面板里的胶囊钮：13pt；实心是强调色配深色字。
    private func pill(_ title: String, height: CGFloat = 30, solid: Bool = false, pro: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if pro { ProBadge() }
            }
            .font(.system(size: 13, weight: solid ? .bold : .semibold))
            .foregroundStyle(solid ? accentInk : .white.opacity(0.92))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if solid {
                    Capsule().fill(accent)
                } else {
                    Capsule().fill(.white.opacity(0.12))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// 对称的竖条波形：`progress` 之前的条是强调色（播放进度）；有 `trim` 时选段里
/// 是强调色、选段外变暗。
struct WaveformBarsView: View {
    var bars: [Float]
    var progress: Double?
    var trim: (Double, Double)?
    var accent: Color

    var body: some View {
        Canvas { ctx, size in
            let n = bars.count
            guard n > 0, size.width > 0 else { return }
            let step = size.width / CGFloat(n)
            let barWidth = max(1, step * 0.58)
            for (i, v) in bars.enumerated() {
                let f = n > 1 ? Double(i) / Double(n - 1) : 0
                var color = Color.white.opacity(0.4)
                if let progress, f <= progress { color = accent }
                if let trim {
                    color = (f >= trim.0 && f <= trim.1) ? accent.opacity(0.95) : .white.opacity(0.22)
                }
                let h = max(2, size.height * CGFloat(v))
                let rect = CGRect(x: CGFloat(i) * step + (step - barWidth) / 2,
                                  y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
