import Foundation

/// Arithmetic for the calculator widget, parsed by hand.
///
/// Not `NSExpression`: it raises an Objective-C exception on input it does
/// not like ("2+", "1/"), which Swift cannot catch, so one stray keystroke
/// would take the whole app down. This is a small recursive-descent parser
/// that fails with an error value instead, and refuses anything beyond plain
/// arithmetic.
///
/// Grammar, loosest first:
///
///     sum      = product (("+" | "-") product)*    a + b% is a × (1 + b%)
///     product  = unary (("*" | "/") unary)*
///     unary    = ("+" | "-") unary | power   so -2^2 is -4
///     power    = postfix ("^" unary)?        right-associative
///     postfix  = atom "%"*                   50% is 0.5
///     atom     = number | "(" sum ")"
public enum Calculator {
    public enum Failure: Error, Equatable, Sendable {
        case empty
        case incomplete
        case unexpected(Character)
        case unbalanced
        case divisionByZero
        case tooLong
        case notFinite

        public var message: String {
            switch self {
            case .empty: tr("请输入算式")
            case .incomplete: tr("算式不完整")
            case .unexpected(let c): tr("无法识别“\(c)”")
            case .unbalanced: tr("括号不匹配")
            case .divisionByZero: tr("不能除以零")
            case .tooLong: tr("算式太长")
            case .notFinite: tr("结果超出范围")
            }
        }
    }

    /// Deep enough for anything typed by hand, shallow enough that a pasted
    /// wall of brackets cannot exhaust the stack.
    static let maxDepth = 64
    static let maxLength = 400

    public static func evaluate(_ text: String) -> Result<Double, Failure> {
        let normalized = normalize(text)
        guard normalized.count <= maxLength else { return .failure(.tooLong) }
        let characters = Array(normalized.filter { !$0.isWhitespace })
        guard !characters.isEmpty else { return .failure(.empty) }
        var parser = Parser(characters: characters)
        do {
            let value = try parser.sum(depth: 0)
            if parser.index < characters.count {
                let c = characters[parser.index]
                throw c == ")" ? Failure.unbalanced : Failure.unexpected(c)
            }
            guard value.isFinite else { throw Failure.notFinite }
            return .success(value == 0 ? 0 : value)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.empty)
        }
    }

    /// The symbols a keyboard, a keypad or a Chinese input method produce,
    /// mapped to the ones the parser reads.
    public static func normalize(_ text: String) -> String {
        var out = ""
        for c in text {
            switch c {
            case "×", "x", "X", "＊": out.append("*")
            case "÷", "／": out.append("/")
            case "−", "–", "－": out.append("-")
            case "＋": out.append("+")
            case "（": out.append("(")
            case "）": out.append(")")
            case "％": out.append("%")
            case "，", ",": continue // thousands separators
            case "。": out.append(".")
            default:
                // Full-width digits.
                if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1,
                   (0xFF10...0xFF19).contains(scalar.value),
                   let digit = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) {
                    out.append(Character(digit))
                } else {
                    out.append(c)
                }
            }
        }
        return out
    }

    /// A result as the display shows it: up to twelve significant figures,
    /// trailing zeros dropped, and exponent notation only where a plain
    /// number would be unreadable.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.6g", value)
        }
        if value == value.rounded(), magnitude < 1e15 {
            return String(format: "%.0f", value)
        }
        let digits = max(0, 11 - Int(floor(log10(magnitude))))
        var text = String(format: "%.\(min(digits, 12))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        private var current: Character? { index < characters.count ? characters[index] : nil }

        /// Where the last `%` ended, so `product` can tell a term that is
        /// nothing but a percentage ("10%") from one that merely contains one.
        var percentEnd = -1
        /// Whether the term `product` just read was a bare percentage.
        var lastTermWasPercent = false

        mutating func sum(depth: Int) throws -> Double {
            var value = try product(depth: depth)
            while let c = current, c == "+" || c == "-" {
                index += 1
                let rhs = try product(depth: depth)
                // 200 + 10% is 220, the way a shop till and every phone
                // calculator read it, not 200.1. Only a bare percentage
                // added to or taken off something; 200 * 10% is still 20.
                if lastTermWasPercent {
                    value = c == "+" ? value * (1 + rhs) : value * (1 - rhs)
                } else {
                    value = c == "+" ? value + rhs : value - rhs
                }
            }
            lastTermWasPercent = false
            return value
        }

        mutating func product(depth: Int) throws -> Double {
            var value = try unary(depth: depth)
            var single = percentEnd == index
            defer { lastTermWasPercent = single }
            while let c = current, c == "*" || c == "/" {
                single = false
                index += 1
                let rhs = try unary(depth: depth)
                if c == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { throw Failure.divisionByZero }
                    value /= rhs
                }
            }
            return value
        }

        mutating func power(depth: Int) throws -> Double {
            let base = try postfix(depth: depth)
            guard current == "^" else { return base }
            index += 1
            guard depth < Calculator.maxDepth else { throw Failure.tooLong }
            let exponent = try unary(depth: depth + 1)
            return pow(base, exponent)
        }

        mutating func unary(depth: Int) throws -> Double {
            guard depth < Calculator.maxDepth else { throw Failure.tooLong }
            if current == "-" {
                index += 1
                let value = try unary(depth: depth + 1)
                return -value
            }
            if current == "+" {
                index += 1
                return try unary(depth: depth + 1)
            }
            return try power(depth: depth)
        }

        mutating func postfix(depth: Int) throws -> Double {
            var value = try atom(depth: depth)
            while current == "%" {
                index += 1
                value /= 100
                percentEnd = index
            }
            return value
        }

        mutating func atom(depth: Int) throws -> Double {
            guard let c = current else { throw Failure.incomplete }
            if c == "(" {
                guard depth < Calculator.maxDepth else { throw Failure.tooLong }
                index += 1
                let value = try sum(depth: depth + 1)
                guard current == ")" else { throw Failure.unbalanced }
                index += 1
                return value
            }
            if c == ")" { throw Failure.unbalanced }
            return try number()
        }

        mutating func number() throws -> Double {
            let start = index
            var sawDot = false
            var sawDigit = false
            while let c = current {
                if c.isASCII, c.isNumber {
                    sawDigit = true
                } else if c == ".", !sawDot {
                    sawDot = true
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit, let value = Double(String(characters[start..<index])) else {
                throw Failure.unexpected(current ?? characters[max(0, min(start, characters.count - 1))])
            }
            return value
        }
    }
}
