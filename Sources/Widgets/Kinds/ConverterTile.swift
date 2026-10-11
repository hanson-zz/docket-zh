import SwiftUI

/// A unit conversion at a glance: what you typed, small, over the answer,
/// large, with the two units as chips beside them and a swap between.
///
/// Typing happens in the panel. A field on the card would take the click
/// that opens it, which is the same reason the sticky note is written in its
/// panel rather than on the shelf.
struct ConverterTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var current: ConverterState { ConverterState(instance.config) }

    var body: some View {
        let state = current
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 3) {
                    Text(UnitConverter.format(state.value) + " " + state.from.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text(state.resultText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                    chip(state.to)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(UnitConverter.format(state.value))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                        Text(state.resultText)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                            .rollingValue(state.resultText)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    Spacer(minLength: 0)
                    VStack(spacing: 1) {
                        chip(state.from)
                        Button {
                            guard !context.isPreview else { return }
                            WidgetWriter.write(instance) { state.swapped.write(into: &$0) }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(WidgetStyle.secondary)
                                .frame(width: 22, height: 12)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("交换单位")
                        chip(state.to)
                    }
                }
            }
        }
    }

    private func chip(_ unit: ConversionUnit) -> some View {
        Text(unit.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WidgetStyle.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minWidth: 30)
            .frame(height: 16)
            .background(WidgetStyle.primary.opacity(0.1), in: .capsule)
    }
}

/// What the converter shows, read from the widget's config.
///
/// Kept under keys the catalog does not default: they are edited in the
/// panel, where the unit menus depend on the category, and the Widgets tab
/// could only offer them as free text that would accept "furlongs".
struct ConverterState: Equatable {
    var category: UnitCategory
    var from: ConversionUnit
    var to: ConversionUnit
    var value: Double

    init(category: UnitCategory, from: ConversionUnit, to: ConversionUnit, value: Double) {
        self.category = category
        self.from = from
        self.to = to
        self.value = value
    }

    init(_ config: WidgetConfig) {
        let category = UnitCategory(rawValue: config.string("category")) ?? .length
        let pair = category.defaultPair
        var from = ConversionUnit(rawValue: config.string("from")) ?? pair.from
        var to = ConversionUnit(rawValue: config.string("to")) ?? pair.to
        if from.category != category { from = pair.from }
        if to.category != category { to = pair.to }
        let value = config.double("value", default: 1)
        self.init(category: category, from: from, to: to, value: value.isFinite ? value : 1)
    }

    var result: Double? { UnitConverter.convert(value, from: from, to: to) }
    var resultText: String { result.map(UnitConverter.format) ?? "-" }

    var swapped: ConverterState {
        ConverterState(category: category, from: to, to: from, value: value)
    }

    func with(category new: UnitCategory) -> ConverterState {
        let pair = new.defaultPair
        return ConverterState(category: new, from: pair.from, to: pair.to, value: value)
    }

    func write(into config: inout WidgetConfig) {
        config.set("category", .string(category.rawValue))
        config.set("from", .string(from.rawValue))
        config.set("to", .string(to.rawValue))
        config.set("value", .number(value))
    }
}
