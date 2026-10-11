import AppKit
import SwiftUI

/// A keypad and a display that also takes the keyboard.
///
/// The answer follows each keystroke; "=" or Return keeps the sum on the
/// card. Parsed by `Calculator`, which reports a bad sum instead of crashing.
struct CalculatorDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft: String?
    @FocusState private var typing: Bool

    private var text: String { draft ?? instance.config.string("expression") }

    private var reading: Result<Double, Calculator.Failure>? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Calculator.evaluate(text)
    }

    private static let keys: [[String]] = [
        ["C", "(", ")", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["%", "0", ".", "⌫"],
    ]

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.orange))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                display
                VStack(spacing: 6) {
                    ForEach(Self.keys, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(row, id: \.self) { key in keyButton(key) }
                        }
                    }
                    keyButton("=")
                }
            }
        }
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField("", text: Binding(get: { text }, set: { draft = $0 }), prompt: Text("输入算式，例如 12×(3+4)"))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.trailing)
                .focused($typing)
                .onSubmit { commit() }
            Group {
                switch reading {
                case .success(let value)?:
                    Text(Calculator.format(value))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                case .failure(let failure)?:
                    Text(failure.message)
                        .foregroundStyle(.white.opacity(0.55))
                case nil:
                    Text("0").foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.system(size: 30, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassPane(cornerRadius: 12)
    }

    private func keyButton(_ key: String) -> some View {
        let isOperator = ["÷", "×", "−", "+", "="].contains(key)
        return Button {
            press(key)
        } label: {
            Text(key)
                .font(.system(size: 16, weight: isOperator ? .bold : .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.white.opacity(key == "=" ? 0.26 : isOperator ? 0.18 : 0.09),
                            in: .rect(cornerRadius: 9, style: .continuous))
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.spoken(key))
    }

    private func press(_ key: String) {
        guard !context.isPreview else { return }
        switch key {
        case "C": draft = ""; commit()
        case "⌫": draft = String(text.dropLast())
        case "=": commit()
        default: draft = text + key
        }
    }

    /// Keeps the sum, and replaces it with its answer so the next key carries
    /// on from the result, the way a pocket calculator does.
    private func commit() {
        let current = text
        var stored = current
        if case .success(let value)? = reading { stored = Calculator.format(value) }
        if current.isEmpty { stored = "" }
        WidgetWriter.write(instance) { $0.set("expression", .string(current)) }
        draft = stored
    }

    private static func spoken(_ key: String) -> String {
        switch key {
        case "C": "清除"
        case "⌫": "删除"
        case "÷": "除"
        case "×": "乘"
        case "−": "减"
        case "+": "加"
        case "=": "等于"
        case "%": "百分号"
        case ".": "小数点"
        default: key
        }
    }
}
