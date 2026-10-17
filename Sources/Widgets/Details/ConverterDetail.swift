import AppKit
import SwiftUI

/// Where the number is typed and the units are chosen, with the same value
/// in every other unit of its kind underneath.
struct ConverterDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @FocusState private var typing: Bool

    private var stored: ConverterState { ConverterState(instance.config) }

    /// The stored state with whatever is being typed applied, so the answer
    /// follows each keystroke without writing the profile on every one.
    private var live: ConverterState {
        var state = stored
        if let typed = UnitConverter.parse(draft) { state.value = typed }
        return state
    }

    var body: some View {
        let state = live
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.orange))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: Binding(
                    get: { state.category },
                    set: { new in save(state.with(category: new)) })) {
                    ForEach(UnitCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    TextField("", text: $draft, prompt: Text("输入数值"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .focused($typing)
                        .onSubmit { commit() }
                        .onChange(of: typing) { _, active in if !active { commit() } }
                    unitMenu(state.from) { save(ConverterState(category: state.category, from: $0,
                                                                to: state.to, value: state.value)) }
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glassPane(cornerRadius: 12)

                HStack {
                    Button {
                        save(state.swapped)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.14), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("交换单位")
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text(state.resultText)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    unitMenu(state.to) { save(ConverterState(category: state.category, from: state.from,
                                                              to: $0, value: state.value)) }
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                .glassPane(cornerRadius: 12)

                others(state)

                PanelButton(title: tr("拷贝结果"), symbol: "doc.on.doc", prominent: true) {
                    ColorSampling.copy(state.resultText)
                }
            }
        }
        .onAppear { draft = UnitConverter.format(stored.value) }
        .onDisappear { commit() }
    }

    private func unitMenu(_ unit: ConversionUnit, choose: @escaping (ConversionUnit) -> Void) -> some View {
        Menu {
            ForEach(unit.category.units, id: \.self) { option in
                Button("\(option.name)（\(option.symbol)）") { choose(option) }
            }
        } label: {
            Text(unit.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.white.opacity(0.16), in: .capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The same quantity in every other unit of its kind.
    private func others(_ state: ConverterState) -> some View {
        let units = state.category.units.filter { $0 != state.from && $0 != state.to }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(units, id: \.self) { unit in
                let value = UnitConverter.convert(state.value, from: state.from, to: unit)
                HStack(spacing: 4) {
                    Text(value.map(UnitConverter.format) ?? "-")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(unit.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .glassPane(cornerRadius: 7)
            }
        }
        .frame(height: 84, alignment: .top)
    }

    private func save(_ state: ConverterState) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { state.write(into: &$0) }
    }

    private func commit() {
        guard let typed = UnitConverter.parse(draft), typed != stored.value else { return }
        var state = stored
        state.value = typed
        save(state)
    }
}
