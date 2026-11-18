import AppKit
import SwiftUI

/// 专注吉祥物的图（Resources/Focus/focus-mascot-<吉祥物>-<状态>.png），读一次就留着。
@MainActor
enum FocusMascotArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ mascot: FocusMascot, _ state: FocusMascotState) -> NSImage? {
        let name = mascot.imageName(state)
        if let image = cache[name] { return image }
        guard !missing.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }
}

/// 一张吉祥物状态图，按高度缩放；换状态时轻轻缩放淡入。
struct FocusMascotImage: View {
    var mascot: FocusMascot
    var state: FocusMascotState
    var height: CGFloat

    var body: some View {
        Group {
            if let image = FocusMascotArt.image(mascot, state), image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: image.size.width * height / image.size.height, height: height)
                    .id(mascot.imageName(state))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: mascot.imageName(state))
        .accessibilityHidden(true)
    }
}

// MARK: - 拖大数字定时长

/// 专注还没开始时，左右（或上下）拖剩余时间的大数字调专注时长：5 分钟一档，5 到 90 分钟，
/// 每换一档触控板轻轻震一下。悬停时光标变成左右箭头、数字底下垫一层淡淡的底。
struct FocusScrubbable: ViewModifier {
    var enabled: Bool
    var minutes: Int
    @Binding var active: Bool
    var apply: (Int) -> Void

    @State private var start: Int?
    @State private var hovering = false
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.panelFill)
                    .opacity(active ? 1 : (hovering && enabled ? 0.7 : 0))
            }
            .overlay(alignment: .bottom) {
                if enabled && (hovering || active) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.panelSecondary)
                        .offset(y: 9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .onHover { inside in
                hovering = inside
                if inside && enabled && !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !inside && cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onChange(of: enabled) { _, now in
                if !now && cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard enabled || start != nil else { return }
                        let base = start ?? minutes
                        if start == nil {
                            start = base
                            active = true
                        }
                        let next = FocusScrub.minutes(from: base, dx: Double(value.translation.width),
                                                      dy: Double(value.translation.height))
                        guard next != minutes else { return }
                        apply(next)
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    .onEnded { _ in
                        start = nil
                        active = false
                    },
                including: enabled || active ? .all : .subviews)
            .help(enabled ? tr("左右拖动调整专注时长（5 到 90 分钟）") : "")
    }
}

// MARK: - 设置里的吉祥物和提示音

/// 六只吉祥物，三列两行，点一下换。
struct FocusMascotPicker: View {
    var selected: FocusMascot
    var accent: Color
    var disabled: Bool
    var pick: (FocusMascot) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(FocusMascot.allCases, id: \.self) { mascot in
                let chosen = mascot == selected
                Button { pick(mascot) } label: {
                    VStack(spacing: 4) {
                        FocusMascotImage(mascot: mascot, state: .idle, height: 44)
                            .frame(height: 44)
                        Text(mascot.title)
                            .font(.system(size: 13, weight: chosen ? .bold : .semibold))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(chosen ? accent.opacity(0.18) : Color.panelFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(chosen ? accent.opacity(0.9) : Color.panelStroke,
                                                  lineWidth: chosen ? 1.4 : 0.6)
                            }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel(mascot.title)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
    }
}

/// 一行提示音：名字、系统声音菜单（选了就试听一下）、试听按钮。
struct FocusSoundRow: View {
    var title: String
    var selection: String
    var repeats: Int
    var accent: Color
    var disabled: Bool
    var choose: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Picker(title, selection: Binding(get: { selection }, set: { name in
                choose(name)
                FocusEndAlert.play(name)
            })) {
                ForEach(FocusEndSound.system, id: \.self) { name in
                    Text(FocusEndSound.title(name)).tag(name)
                }
                Divider()
                Text(FocusEndSound.title(FocusEndSound.none)).tag(FocusEndSound.none)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .tint(accent)
            .disabled(disabled)
            Button {
                FocusEndAlert.play(selection, times: repeats)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selection == FocusEndSound.none ? Color.panelQuaternary : Color.panelPrimary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(disabled || selection == FocusEndSound.none)
            .help(tr("试听"))
            .accessibilityLabel(tr("试听\(title)"))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}
