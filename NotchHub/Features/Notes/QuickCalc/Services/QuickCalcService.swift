import AppKit
import Foundation
import Observation
import OSLog

/// One copied calculation.
struct QuickCalcHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let expression: String
    let result: String

    init(id: UUID = UUID(), expression: String, result: String) {
        self.id = id
        self.expression = expression
        self.result = result
    }
}

/// State behind the Notes module's "Hesap" segment: the live input, its result, the last five
/// copied calculations and the "Hızlı hesap" setting.
@MainActor
@Observable
final class QuickCalcService {
    static let historyLimit = 5

    private enum Keys {
        static let isEnabled = "quickCalcEnabled"
        static let history = "quickCalcHistory"
    }

    /// Settings › "Hızlı hesap"; on by default. Off hides the segment.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled { isActive = false }
        }
    }

    /// True while the "Hesap" segment is selected instead of the notes.
    private(set) var isActive = false
    /// Set when the user picks the segment, so the field takes keyboard focus once (never on hover-open).
    var wantsFocus = false

    var input = "" {
        didSet { reevaluate() }
    }

    private(set) var outcome: QuickCalcOutcome = .empty
    private(set) var history: [QuickCalcHistoryEntry]

    let rateStore: CurrencyRateStore

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let evaluator: QuickCalcEvaluator
    @ObservationIgnored let formatter: QuickCalcFormatter
    @ObservationIgnored private let copy: @MainActor (String) -> Void
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "QuickCalc")

    init(
        defaults: UserDefaults = .standard,
        rateStore: CurrencyRateStore? = nil,
        locale: Locale = .autoupdatingCurrent,
        copy: @escaping @MainActor (String) -> Void = QuickCalcService.copyToPasteboard
    ) {
        self.defaults = defaults
        self.rateStore = rateStore ?? CurrencyRateStore(
            fetcher: OpenERAPIRatesFetcher(),
            cache: UserDefaultsCurrencyRatesCache(defaults: defaults)
        )
        evaluator = QuickCalcEvaluator(locale: locale)
        formatter = QuickCalcFormatter(locale: locale)
        self.copy = copy
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        history = Self.loadHistory(from: defaults)
    }

    // MARK: - Mode

    func setActive(_ active: Bool) {
        guard isEnabled || !active else { return }
        isActive = active
        wantsFocus = active
    }

    // MARK: - Results

    /// The current value, when the input evaluates.
    var value: QuickCalcValue? {
        if case .value(let value) = outcome { return value }
        return nil
    }

    var displayText: String? {
        value.map(formatter.display)
    }

    /// Copies the result and records it; false when there is nothing to copy.
    @discardableResult
    func commit() -> Bool {
        guard let value else { return false }
        copy(formatter.copyText(value))
        record(QuickCalcHistoryEntry(expression: input.trimmingCharacters(in: .whitespaces), result: formatter.display(value)))
        return true
    }

    func reuse(_ entry: QuickCalcHistoryEntry) {
        input = entry.expression
        wantsFocus = true
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    /// Re-runs the evaluation, fetching rates first when a currency conversion needs (fresher) ones.
    func refreshRatesIfNeeded() async {
        guard needsRateRefresh else { return }
        await rateStore.refreshIfNeeded()
        reevaluate()
    }

    private var needsRateRefresh: Bool {
        switch outcome {
        case .needsRates: true
        case .value(.currency): !rateStore.isFresh
        default: false
        }
    }

    private func reevaluate() {
        outcome = evaluator.evaluate(input, rates: rateStore.rates)
    }

    // MARK: - History

    private func record(_ entry: QuickCalcHistoryEntry) {
        let isRepeat = history.first.map { $0.expression == entry.expression && $0.result == entry.result } ?? false
        guard !isRepeat else { return }
        history = Array(([entry] + history).prefix(Self.historyLimit))
        saveHistory()
    }

    private func saveHistory() {
        do {
            defaults.set(try JSONEncoder().encode(history), forKey: Keys.history)
        } catch {
            logger.error("Could not save calculation history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadHistory(from defaults: UserDefaults) -> [QuickCalcHistoryEntry] {
        guard let data = defaults.data(forKey: Keys.history) else { return [] }
        let entries = (try? JSONDecoder().decode([QuickCalcHistoryEntry].self, from: data)) ?? []
        return Array(entries.prefix(historyLimit))
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
