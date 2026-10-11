import AppKit

/// The system's own eyedropper.
///
/// `NSColorSampler` is the magnifying loupe macOS draws for every colour well
/// and it needs no permission: it hands back the one pixel the user clicked
/// and nothing else, so no screen recording consent is involved.
@MainActor
enum ColorSampling {
    /// Kept for the duration of a sample; the sampler is not guaranteed to
    /// keep itself alive.
    private static var sampler: NSColorSampler?

    static func sample(_ done: @escaping @MainActor @Sendable (ColorCode) -> Void) {
        guard sampler == nil else { return }
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            let code = color.flatMap { $0.usingColorSpace(.sRGB) }.map {
                ColorCode(red: Double($0.redComponent),
                          green: Double($0.greenComponent),
                          blue: Double($0.blueComponent))
            }
            Task { @MainActor in
                ColorSampling.sampler = nil
                if let code { done(code) }
            }
        }
    }

    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}
