import Foundation

/// Whether a widget draws its own card on the shelf.
///
/// Stored in the widget's config under `hidePlate`, not as a field on
/// `WidgetInstance`: config already tolerates keys it does not know, so a
/// build that predates this ignores it and nothing has to migrate.
public enum WidgetPlate {
    public static let key = "hidePlate"

    public static func isHidden(_ config: WidgetConfig) -> Bool {
        config.bool(key)
    }

    public static func toggled(_ instance: WidgetInstance) -> WidgetInstance {
        var copy = instance
        copy.config.set(key, .bool(!isHidden(instance.config)))
        return copy
    }
}
