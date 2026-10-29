import Foundation

/// SplitMix64: a tiny, fast, seedable generator so the bar motion is reproducible in tests.
struct SeededRandomSource: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return Self.mix(state)
    }

    /// The SplitMix64 finalizer, also used as a stateless hash.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Pseudo-random, organic equalizer levels: smooth value noise per bar, two octaves, no audio capture.
/// Levels are pure functions of time, so a paused `TimelineView` simply freezes them.
struct EqualizerBarGenerator: Sendable {
    static let defaultBarCount = 4
    static let minimumLevel = 0.2
    static let maximumLevel = 1.0
    /// Level every bar shrinks to while paused.
    static let restingLevel = 0.2
    /// Fixed staggered shape shown when motion is off (Reduce Motion, Low Power Mode, hidden).
    static let staticPattern: [Double] = [0.45, 0.8, 0.6, 0.9, 0.5]
    /// Noise lattice points per second, per bar.
    static let rateRange: ClosedRange<Double> = 3.2...6.2
    /// Weight of the faster second octave that adds flicker on top of the slow swell.
    static let detailWeight = 0.35

    let barCount: Int
    private let seed: UInt64
    private let rates: [Double]
    private let offsets: [Double]

    init(barCount: Int = EqualizerBarGenerator.defaultBarCount, seed: UInt64) {
        let count = max(barCount, 0)
        var source = SeededRandomSource(seed: seed)
        var rates: [Double] = []
        var offsets: [Double] = []
        for _ in 0..<count {
            rates.append(Double.random(in: Self.rateRange, using: &source))
            offsets.append(Double.random(in: 0..<1_000, using: &source))
        }
        self.barCount = count
        self.seed = seed
        self.rates = rates
        self.offsets = offsets
    }

    /// Animated levels in `minimumLevel...maximumLevel`, continuous in `time`.
    func levels(at time: TimeInterval) -> [Double] {
        (0..<barCount).map { level(bar: $0, time: time) }
    }

    var restingLevels: [Double] {
        Array(repeating: Self.restingLevel, count: barCount)
    }

    var staticLevels: [Double] {
        (0..<barCount).map { Self.staticPattern[$0 % Self.staticPattern.count] }
    }

    // MARK: - Private

    private func level(bar: Int, time: TimeInterval) -> Double {
        let position = time * rates[bar] + offsets[bar]
        let base = noise(bar: bar, octave: 0, position: position)
        let detail = noise(bar: bar, octave: 1, position: position * 2.3)
        let combined = (base + Self.detailWeight * detail) / (1 + Self.detailWeight)
        return Self.minimumLevel + (Self.maximumLevel - Self.minimumLevel) * combined
    }

    /// Smoothstep-interpolated value noise in 0...1.
    private func noise(bar: Int, octave: Int, position: Double) -> Double {
        let cell = position.rounded(.down)
        let fraction = position - cell
        let index = Int64(cell)
        let start = latticeValue(bar: bar, octave: octave, index: index)
        let end = latticeValue(bar: bar, octave: octave, index: index &+ 1)
        let eased = fraction * fraction * (3 - 2 * fraction)
        return start + (end - start) * eased
    }

    private func latticeValue(bar: Int, octave: Int, index: Int64) -> Double {
        let barKey = UInt64(bar) &* 0x9E37_79B9_7F4A_7C15
        let octaveKey = UInt64(octave) &* 0xC2B2_AE3D_27D4_EB4F
        let hashed = SeededRandomSource.mix(seed ^ barKey ^ octaveKey ^ UInt64(bitPattern: index))
        return Double(hashed >> 11) / Double(1 << 53)
    }
}
