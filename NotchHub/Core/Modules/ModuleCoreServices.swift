import Foundation

/// The feature services `ModuleServices` is built from, plus the defaults its monitors read.
/// The app uses `live()`; screenshot rendering passes demo instances backed by fixtures.
@MainActor
struct ModuleCoreServices {
    let defaults: UserDefaults
    let shelf: ShelfStore
    let clipboard: ClipboardHistoryStore
    let media: MediaService
    let audio: AudioOutputService
    let timer: TimerService
    let calendar: CalendarService
    let notes: NoteStore
    let calculator: QuickCalcService
    let weather: WeatherService

    /// Production services reading the user's real stores.
    static func live() -> ModuleCoreServices {
        liveCreationCount += 1
        return ModuleCoreServices(
            defaults: .standard,
            shelf: ShelfStore(),
            clipboard: ClipboardHistoryStore(),
            media: MediaService(),
            audio: AudioOutputService(),
            timer: TimerService(),
            calendar: CalendarService(),
            notes: NoteStore(),
            calculator: QuickCalcService(),
            weather: WeatherService()
        )
    }

    /// How often `live()` ran in this process; screenshot mode checks that it stays zero.
    private(set) static var liveCreationCount = 0
}
