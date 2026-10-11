import AppKit
import SwiftUI

/// Every open app, with its name; a click brings it forward, and a secondary
/// click hides or quits it.
struct AppSwitcherDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var catalog: AppCatalog { AppCatalog.shared }

    private var apps: [AppSwitcherItem] {
        if context.isPreview { return AppSwitcherItem.samples }
        return AppStrip.ordered(catalog.running, isActive: \.isActive)
            .map { AppSwitcherItem(id: $0.id, name: $0.name, url: $0.url, isActive: $0.isActive) }
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "square.grid.3x2", title: "应用切换器",
                            subtitle: "\(apps.count) 个应用正在运行")
                if apps.isEmpty {
                    PanelNote(symbol: "macwindow", text: "没有正在运行的应用。").frame(height: 160)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                                  spacing: 8) {
                            ForEach(apps) { app in cell(app) }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(236, CGFloat((apps.count + 3) / 4) * 78))
                }
            }
        }
        .onAppear { if !context.isPreview { catalog.refresh() } }
    }

    private func cell(_ app: AppSwitcherItem) -> some View {
        VStack(spacing: 4) {
            AppSwitcherIcon(app: app, size: 40)
            Text(app.name)
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(app.isActive ? 1 : 0.75))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if app.isActive {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.1))
            }
        }
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            guard !context.isPreview else { return }
            _ = catalog.activate(bundleID: app.id)
        }
        .contextMenu {
            if !context.isPreview {
                Button("切换到此应用") { _ = catalog.activate(bundleID: app.id) }
                Button("隐藏") { _ = running(app)?.hide() }
                Divider()
                Button("退出") { _ = running(app)?.terminate() }
            }
        }
        .help(app.name)
    }

    private func running(_ app: AppSwitcherItem) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first
    }
}
