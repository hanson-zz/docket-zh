import AppKit

/// Borrows Apple's Dock reserved strip so zoomed windows stop at the shelf.
///
/// See `DockStrut` for why this is the only route that works. The short of it
/// is that the Dock is the only thing that can reserve screen space, so the
/// shelf stops competing with it and sits on top of it instead.
///
/// Everything here is about giving it back. Docket is changing settings that
/// belong to the user and that no other app will repair, so the rules are:
/// ask before the first time, write down what was there before changing
/// anything, and treat a recorded snapshot as a debt that gets paid at the
/// next opportunity however the app went away last time.
@MainActor
public enum StrutMode {

    /// Whether the shelf should be borrowing the strip right now.
    public static func wanted(for setup: DockSetup) -> Bool { setup == .customReplacement }

    // MARK: Entering

    /// Takes the strip, if the user agrees, and reports the thickness reserved.
    ///
    /// Returns nil when nothing was claimed, which the caller should treat as
    /// "stay in the previous mode" rather than as a failure to report.
    public static func enter(edge: DockPosition,
                             wanting thickness: CGFloat,
                             state: PersistedState,
                             record: (DockPrefs) -> Void) async -> CGFloat? {
        // Already borrowed. Re-measure rather than re-ask: the Dock may have
        // been restarted by something else since.
        if state.borrowedDockPrefs != nil {
            return DockStrut.thickness(on: edge)
        }
        guard consent(edge: edge) else { return nil }

        // Recorded before anything is written, so an interruption between here
        // and the write still leaves a correct restore.
        let before = DockStrut.snapshot()
        record(before)

        return await DockStrut.claim(edge: edge, tileSize: tileSize(forStrip: thickness))
    }

    // MARK: Leaving

    /// Puts the Dock back, and clears the debt only once that has happened.
    public static func leave(state: PersistedState, clear: @escaping () -> Void) async {
        guard let borrowed = state.borrowedDockPrefs else { return }
        await DockStrut.release(borrowed)
        clear()
    }

    /// Called at launch. A snapshot still recorded means the app went away
    /// without putting the Dock back, so it is put back now.
    ///
    /// Deliberately unconditional on the current mode: if the user has since
    /// switched away from the replacement setup, the debt is still owed.
    public static func repayIfOwed(state: PersistedState,
                                   clear: @escaping () -> Void) async {
        guard state.borrowedDockPrefs != nil, !wanted(for: state.setup) else { return }
        await leave(state: state, clear: clear)
    }

    // MARK: Sizing

    /// See `DockStrutMetrics`, which is where the sizing lives so it can be
    /// tested without building a shelf.
    static func tileSize(forStrip strip: CGFloat) -> Double {
        DockStrutMetrics.tileSize(forStrip: strip)
    }

    // MARK: Consent

    /// Asked once, plainly, because the honest description of this is
    /// "Docket would like to change your Dock settings".
    private static func consent(edge: DockPosition) -> Bool {
        // A modal alert cannot be answered by a test harness, and this is the
        // one path in the app that blocks on a person. The same escape hatch
        // the library and settings windows already use.
        if ProcessInfo.processInfo.environment["DOCKET_STRUT_CONSENT"] != nil { return true }

        let alert = NSAlert()
        alert.messageText = "允许码头管理你的程序坞吗？"
        alert.informativeText = """
            只有程序坞预留了屏幕空间，窗口才会停在扩展栏边上，而这只有程序坞本身能做到。\
            Docket 会把系统程序坞移到屏幕\(edge.displayName)，关闭其自动隐藏，\
            将其大小调整为与扩展栏一致，然后用扩展栏覆盖它。

            你当前的程序坞设置会被保存，在关闭此功能或退出 Docket 时恢复。
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "管理我的程序坞")
        alert.addButton(withTitle: "取消")
        // An accessory app has no windows of its own to be modal to, and the
        // alert has to come forward or it is answered blind.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
