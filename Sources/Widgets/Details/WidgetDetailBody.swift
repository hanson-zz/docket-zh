import SwiftUI

/// Routes a widget to its own detail content.
///
/// One switch rather than a protocol with two dozen conformances: the bodies
/// have nothing in common beyond being a view, and the chrome around them is
/// already shared by `WidgetDetailChrome`.
struct WidgetDetailBody: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        switch instance.kind {
        case .music:
            MusicDetail(instance: instance, context: context)
        case .timer:
            FocusTimerDetail(instance: instance, context: context)
        case .calendar:
            CalendarDetail(instance: instance, context: context)
        case .battery:
            BatteryDetail(instance: instance, context: context)
        case .system:
            SystemActivityDetail(instance: instance, context: context)
        case .notes:
            StickyNoteDetail(instance: instance, context: context)
        case .stripe, .paddle, .shopify:
            RevenueDetail(instance: instance, context: context)
        case .stock, .watchlist:
            StocksDetail(instance: instance, context: context)
        case .weather:
            WeatherDetail(instance: instance, context: context)
        case .clock:
            ClockDetail(instance: instance, context: context)
        case .world:
            WorldClockDetail(instance: instance, context: context)
        case .stopwatch:
            StopwatchDetail(instance: instance, context: context)
        case .countdown:
            CountdownDetail(instance: instance, context: context)
        case .alarm:
            AlarmDetail(instance: instance, context: context)
        case .progress:
            TimeProgressDetail(instance: instance, context: context)
        case .network:
            NetworkDetail(instance: instance, context: context)
        case .airdrop:
            AirDropDetail(instance: instance, context: context)
        case .reminders:
            RemindersDetail(instance: instance, context: context)
        case .shortcut:
            ShortcutDetail(instance: instance, context: context)
        case .photos:
            PhotoFrameDetail(instance: instance, context: context)
        case .screenshots:
            ScreenshotsDetail(instance: instance, context: context)
        case .downloads:
            DownloadsDetail(instance: instance, context: context)
        case .fileShelf:
            FileShelfDetail(instance: instance, context: context)
        case .clipboard:
            ClipboardDetail(instance: instance, context: context)
        case .colorPicker:
            ColorPickerDetail(instance: instance, context: context)
        case .converter:
            ConverterDetail(instance: instance, context: context)
        case .search:
            SearchDetail(instance: instance, context: context)
        case .github:
            GitHubDetail(instance: instance, context: context)
        case .currency:
            CurrencyDetail(instance: instance, context: context)
        case .calculator:
            CalculatorDetail(instance: instance, context: context)
        case .recorder:
            RecorderDetail(instance: instance, context: context)
        case .bookmarks:
            BookmarksDetail(instance: instance, context: context)
        case .appSwitcher:
            AppSwitcherDetail(instance: instance, context: context)
        case .wallpaper:
            WallpaperDetail(instance: instance, context: context)
        case .posture:
            PostureDetail(instance: instance, context: context)
        case .aiUsage:
            CodexUsageDetail(instance: instance, context: context)
        case .todo:
            TodoDetail(instance: instance, context: context)
        case .ambient:
            AmbientDetail(instance: instance, context: context)
        case .lunar:
            LunarDetail(instance: instance, context: context)
        case .trash:
            TrashDetail(instance: instance, context: context)
        case .habit:
            HabitDetail(instance: instance, context: context)
        case .week:
            WeekDetail(instance: instance, context: context)
        case .crypto:
            CryptoDetail(instance: instance, context: context)
        case .appVolume:
            AppVolumeDetail(instance: instance, context: context)
        case .radio:
            RadioDetail(instance: instance, context: context)
        case .anniversary:
            AnniversaryDetail(instance: instance, context: context)
        case .water:
            WaterDetail(instance: instance, context: context)
        case .translate:
            TranslateDetail(instance: instance, context: context)
        default:
            // Nothing reaches this now that every placeable kind has a
            // panel. Better an honest line than a panel that explains its
            // own absence.
            Text("此小组件没有更多详情。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The colour this panel should stand on, if its widget has one.
    ///
    /// Here rather than in the chrome so the chrome gains no knowledge of
    /// kinds, and here rather than a PreferenceKey because the panel reads
    /// its own fitting size exactly once and a preference travelling up
    /// through that measurement is a risk taken for nothing.
    @MainActor
    static func ground(_ instance: WidgetInstance, _ context: WidgetContext) -> ArtworkTint? {
        switch instance.kind {
        case .music: MusicDetail.ground(instance: instance, context: context)
        default: nil
        }
    }
}
