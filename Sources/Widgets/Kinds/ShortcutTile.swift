import SwiftUI

/// 一排快捷指令，点一下就跑。
///
/// 卡片放列表前 4 个圆角图标，颜色和图标是面板“外观”里给它挑的；多出来
/// 的只在面板里。卡片宽度按图标个数算（`ShortcutDeck.tileWidth`），一个都没
/// 选时画原来的“选择”，点卡片打开面板去勾选。
///
/// 正在跑的那个图标换成停止键，再点一下就停。跑不出进度，能做的只有停，
/// 所以不画转圈。失败的在右上角挂一个红点，原因去面板里看。
struct ShortcutTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: ShortcutsService { ShortcutsService.shared }

    var body: some View {
        let column = context.position.isVertical
        let items = shown
        return WidgetSurface {
            if items.isEmpty {
                empty(column: column)
            } else if column {
                LazyVGrid(columns: [GridItem(.fixed(ShortcutDeck.columnIconSize), spacing: 4),
                                    GridItem(.fixed(ShortcutDeck.columnIconSize), spacing: 4)],
                          spacing: 4) {
                    ForEach(items) { item in button(item, size: ShortcutDeck.columnIconSize) }
                }
            } else {
                HStack(spacing: ShortcutDeck.iconSpacing) {
                    ForEach(items) { item in button(item, size: ShortcutDeck.iconSize) }
                }
            }
        }
    }

    // MARK: Pieces

    /// 原来的“选择”：卡片自己的点击打开面板，在那里勾选。
    @ViewBuilder private func empty(column: Bool) -> some View {
        if column {
            VStack(spacing: 5) {
                TileGlyph(symbol: "plus", size: 13, action: nil)
                Text(tr("选择"))
                    .font(WidgetStyle.label(11))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 10) {
                TileGlyph(symbol: "plus", size: 12, action: nil)
                TileReading(value: tr("选择"), caption: tr("快捷指令"), valueSize: 15)
                Spacer(minLength: 0)
            }
        }
    }

    /// 只有图标本身能点，卡片其余地方的点击照样打开面板。
    private func button(_ item: ShortcutItem, size: CGFloat) -> some View {
        let running = !context.isPreview && service.isRunning(item.name)
        var failed = false
        if !context.isPreview, !running, case .failed = service.record(for: item.name)?.status {
            failed = true
        }
        return Button {
            guard !context.isPreview else { return }
            if running { service.stop(item.name) } else { service.run(item.name) }
        } label: {
            ShortcutIcon(item: item, size: size, running: running)
                .overlay(alignment: .topTrailing) {
                    if failed {
                        Circle()
                            .fill(Color(hex: "#FF6B5A"))
                            .frame(width: size * 0.24, height: size * 0.24)
                            .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1) }
                            .offset(x: size * 0.06, y: -size * 0.06)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
        .accessibilityLabel(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
    }

    /// 小组件库里没有真的快捷指令可放，画两个示例图标（新卡片 140 宽放得下），不能点。
    private var shown: [ShortcutItem] {
        if context.isPreview {
            return [
                ShortcutItem(name: tr("专注模式"), color: .indigo, symbol: .moon),
                ShortcutItem(name: tr("图片压缩"), color: .orange, symbol: .photo),
            ]
        }
        return ShortcutDeck.tileItems(instance.config)
    }
}

/// 快捷指令的圆角图标：色块上一枚白色 SF Symbol。卡片、面板和编辑态共用。
struct ShortcutIcon: View {
    var item: ShortcutItem
    var size: CGFloat
    /// 正在跑时图标换成停止键，色块变暗一点。
    var running = false

    var body: some View {
        let colour = Color(hex: item.color.hex)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(running ? colour.mix(with: .black, by: 0.35) : colour)
            Image(systemName: running ? "stop.fill" : item.symbol.systemName)
                .font(.system(size: size * (running ? 0.36 : 0.46), weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .contentShape(.rect(cornerRadius: size * 0.28, style: .continuous))
    }
}
