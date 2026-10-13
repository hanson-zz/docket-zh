import SwiftUI

/// The flies on the shelf's own Trash icon, the same swarm the 废纸篓 widget
/// draws (`FlySwarm`), sized to the icon.
///
/// Counted by `TrashMonitor` against the size chosen in settings, so they
/// arrive and multiply exactly as they do on the widget, and the pointer
/// scares them off. Without Full Disk Access the Trash cannot be measured,
/// and the icon simply has no flies: it is still the Trash, and asking for
/// a permission belongs to the widget, which has room to explain it.
struct ShelfTrashFlies: View {
    /// The icon's side in points.
    var side: CGFloat
    var threshold: Int64
    var hovering: Bool

    private var monitor: TrashMonitor { TrashMonitor.shared }
    @State private var scaredAt: Date?

    var body: some View {
        // The count only moves with the Trash's size (observed) or the hour
        // (one more fly per hour over), so a minute's tick is plenty; the
        // swarm animates itself.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            FlySwarm(count: monitor.flies(now: timeline.date, threshold: threshold),
                     scaredAt: scaredAt, hovering: hovering, animated: true,
                     flySize: CGFloat(TrashFlies.flyScale(side: Double(side))))
                .frame(width: side * 1.7, height: side * 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { monitor.start(threshold: threshold) }
        .onChange(of: threshold) { _, now in monitor.start(threshold: now) }
        .onChange(of: hovering) { _, inside in
            // Entering scares them; leaving starts the slow return.
            scaredAt = inside ? .now : .now.addingTimeInterval(-0.6)
        }
    }
}
