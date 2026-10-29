import SwiftUI

/// `Section("Zamanlayıcı")` for the grouped settings Form.
struct TimerSettingsSection: View {
    @Bindable var timer: TimerService

    init(timer: TimerService) {
        self.timer = timer
    }

    var body: some View {
        Section("Zamanlayıcı") {
            minutesStepper("Odak", value: $timer.pomodoroSettings.workMinutes, range: PomodoroSettings.workMinutesRange)
            minutesStepper(
                "Kısa mola",
                value: $timer.pomodoroSettings.shortBreakMinutes,
                range: PomodoroSettings.shortBreakMinutesRange
            )
            minutesStepper(
                "Uzun mola",
                value: $timer.pomodoroSettings.longBreakMinutes,
                range: PomodoroSettings.longBreakMinutesRange
            )
            Stepper(value: $timer.pomodoroSettings.sessionsBeforeLongBreak, in: PomodoroSettings.sessionsRange) {
                LabeledContent("Uzun molaya kadar oturum") {
                    Text("\(timer.pomodoroSettings.sessionsBeforeLongBreak)")
                        .monospacedDigit()
                }
            }
            Toggle("Sonraki aşamayı otomatik başlat", isOn: $timer.pomodoroSettings.autoStartNextPhase)
        }
    }

    private func minutesStepper(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title) {
                Text("\(value.wrappedValue) dk")
                    .monospacedDigit()
            }
        }
    }
}
