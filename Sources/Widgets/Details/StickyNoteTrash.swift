import SwiftUI

// MARK: - 撕纸动画

/// 正在飞进垃圾桶的一张纸：撕下来那一刻的样子、它在面板里的位置，和到垃圾桶的距离。
struct StickyFlight: Identifiable, Equatable {
    let id = UUID()
    var paper: PaperColor
    var text: String
    var font: StickyNoteFont
    var size: CGFloat
    /// 纸在面板里的位置。
    var frame: CGRect
    /// 从纸的中心到垃圾桶中心。
    var target: CGSize
    var startedAt = Date()
}

/// 撕纸：从胶带下撕开（顶边变成毛边，纸往下一沉、微微歪），右下角卷起离开，
/// 卷成一小卷飞进顶栏的垃圾桶。约 0.5 秒。减少动态效果时原地淡出。
///
/// 只在撕的那半秒画，画完 `StickyNoteDetail` 把它拿掉，不常驻计时器。
struct StickyTearFlight: View {
    var flight: StickyFlight
    var reduceMotion: Bool

    static let motionDuration = 0.5
    static let fadeDuration = 0.25

    static func duration(_ reduceMotion: Bool) -> Double {
        reduceMotion ? fadeDuration : motionDuration
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(flight.startedAt)
            if reduceMotion {
                paper(torn: false)
                    .opacity(max(0, 1 - elapsed / Self.fadeDuration))
            } else {
                let t = min(1, max(0, elapsed / Self.motionDuration))
                let pose = StickyTearPose(t: t, target: flight.target)
                paper(torn: true)
                    .rotation3DEffect(.degrees(pose.curl), axis: (x: -1, y: 1, z: 0),
                                      anchor: .topLeading, perspective: 0.5)
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.spin))
                    .offset(x: pose.offset.width, y: pose.offset.height)
                    .opacity(pose.opacity)
            }
        }
    }

    private func paper(torn: Bool) -> some View {
        let ink = Color(hex: flight.paper.inkHex)
        return ZStack(alignment: .topLeading) {
            Color(hex: flight.paper.hex)
            Text(verbatim: StickyChecklist.display(flight.text))
                .font(StickyFont.font(flight.font, size: flight.size))
                .foregroundStyle(ink)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(StickyTornEdge(teeth: torn ? 16 : 0))
        .shadow(color: .black.opacity(0.22), radius: 4, x: 1, y: 3)
    }
}

/// 撕纸每一刻的姿势。0 到 0.2 撕开下沉，0.15 到 0.5 卷角，0.45 起卷成一小卷飞走。
struct StickyTearPose {
    var curl: Double
    var scale: CGFloat
    var spin: Double
    var offset: CGSize
    var opacity: Double

    init(t: Double, target: CGSize) {
        func phase(_ from: Double, _ to: Double) -> Double {
            let x = min(1, max(0, (t - from) / (to - from)))
            return x * x * (3 - 2 * x)
        }
        let lift = phase(0, 0.2)
        let roll = phase(0.15, 0.5)
        let fly = phase(0.45, 1)
        let flyIn = fly * fly
        curl = 58 * roll
        scale = CGFloat((1 - 0.18 * roll) * (1 - 0.88 * flyIn))
        spin = -3 * lift + 160 * flyIn
        // 飞的时候往上拱一点，像扔出去的纸团。
        let arc = -28 * sin(Double.pi * fly)
        offset = CGSize(width: target.width * flyIn,
                        height: 6 * lift + target.height * flyIn + arc)
        opacity = 1 - 0.8 * max(0, (fly - 0.6) / 0.4)
    }
}

/// 撕开的纸：顶边是一排小锯齿（从胶带下撕的毛边），其余是小圆角。`teeth` 为 0 时就是圆角矩形。
struct StickyTornEdge: Shape {
    var teeth: Int

    func path(in rect: CGRect) -> Path {
        guard teeth > 0 else {
            return Path(roundedRect: rect, cornerRadius: 4, style: .continuous)
        }
        var path = Path()
        let depth: CGFloat = 4
        let step = rect.width / CGFloat(teeth)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        for i in 0..<teeth {
            let x = rect.minX + CGFloat(i) * step
            // 齿高错落一点，不像尺子画的。
            let peak = rect.minY + (i % 3 == 1 ? depth * 0.2 : 0)
            path.addLine(to: CGPoint(x: x + step * 0.5, y: peak))
            path.addLine(to: CGPoint(x: x + step, y: rect.minY + depth))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 4), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 垃圾桶

/// 最近撕掉的便签：恢复（放回最上面）、彻底删除、清空（要确认）。
/// 留 7 天、最多 30 张。空的时候小熊猫歇着。
struct StickyTrashPanel: View {
    var instance: WidgetInstance
    var back: () -> Void

    @State private var hovered: String?
    @State private var confirmEmpty = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var entries: [StickyTrash.Entry] { StickyTrash.entries(instance.config, now: Date()) }
    private var canRestore: Bool { StickyTrash.canRestore(instance.config) }
    private var listAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }

    var body: some View {
        let entries = self.entries
        return VStack(alignment: .leading, spacing: 12) {
            header(empty: entries.isEmpty)
            Text(tr("保留 7 天或最近 30 张，过期自动删除"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { entry in row(entry) }
                    }
                }
                .frame(maxHeight: 380)
                .scrollIndicators(.never)
                Text(tr("恢复的便签放回最上面"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
        }
        .confirmationDialog(tr("清空垃圾桶？"), isPresented: $confirmEmpty) {
            Button(tr("清空"), role: .destructive) {
                withAnimation(listAnimation) { StickyLog.emptyTrash(instance) }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("\(entries.count) 张便签会被彻底删除，不能恢复。"))
        }
    }

    /// 「‹ 便签」、标题、「清空」排一行：标题占中间剩下的宽度，英文长一点时缩一点（不小于 13pt），
    /// 不和两边的按钮叠在一起。
    private func header(empty: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: back) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("便签"))
                        .font(WidgetStyle.label(13))
                        .fixedSize()
                }
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(.panelFill))
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(tr("返回便签"))
            Text(tr("最近撕掉"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button { confirmEmpty = true } label: {
                Text(tr("清空"))
                    .font(WidgetStyle.label(13))
                    .fixedSize()
                    .foregroundStyle(Color(hex: PaletteColor.red.hex).panelReadable)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .opacity(empty ? 0.45 : 1)
        }
    }

    private func row(_ entry: StickyTrash.Entry) -> some View {
        let showing = hovered == entry.id
        let paper = PaperColor(rawValue: entry.sheet.color) ?? .yellow
        let title = entry.title.isEmpty ? tr("空白便签") : entry.title
        return HStack(spacing: 10) {
            thumbnail(paper)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "\(StickyTrash.age(of: entry.tornAt, now: Date())) · \(entry.summary)")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if showing {
                Button {
                    withAnimation(listAnimation) { StickyLog.restore(entry.id, in: instance) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tr("恢复"))
                            .font(WidgetStyle.label(13))
                            .fixedSize()
                    }
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(.panelRaised).panelLift())
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(!canRestore)
                .opacity(canRestore ? 1 : 0.45)
                .help(canRestore ? tr("放回最上面") : tr("便签已经叠满 \(StickyStack.limit) 张，先撕掉一张"))
                Button {
                    withAnimation(listAnimation) { StickyLog.deleteForever(entry.id, in: instance) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: PaletteColor.red.hex).panelReadable)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.panelFill))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(tr("彻底删除"))
                .accessibilityLabel(tr("彻底删除"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(showing ? Color.panelSelected : Color.clear)
        }
        .contentShape(.rect)
        .onHover { inside in
            if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(tr("恢复"))) {
            guard canRestore else { return }
            StickyLog.restore(entry.id, in: instance)
        }
        .accessibilityAction(named: Text(tr("彻底删除"))) {
            StickyLog.deleteForever(entry.id, in: instance)
        }
    }

    /// 列表里的小纸片：那张纸的颜色、一条胶带、三道淡墨线。
    private func thumbnail(_ paper: PaperColor) -> some View {
        let ink = Color(hex: paper.inkHex)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: paper.hex))
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0.5, y: 1)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<3, id: \.self) { line in
                        Capsule()
                            .fill(ink.opacity(0.22))
                            .frame(width: line == 2 ? 14 : 24, height: 2)
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 7)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(.white.opacity(paper.isDark ? 0.28 : 0.5))
                    .frame(width: 16, height: 5)
                    .offset(y: -2)
            }
            .frame(width: 38, height: 42)
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if let image = PandaArt.image("pet-panda-rest") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)
            }
            Text(tr("这里空空的"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Text(tr("撕掉的便签会在这里待 7 天"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}
