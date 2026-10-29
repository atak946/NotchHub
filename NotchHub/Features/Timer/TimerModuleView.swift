import SwiftUI

/// Main Timer content for the expanded panel (~590 × 160 pt).
struct TimerModuleView: View {
    let timer: TimerService

    init(timer: TimerService) {
        self.timer = timer
    }

    var body: some View {
        Group {
            if timer.state == .idle {
                TimerIdleView(timer: timer)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                TimerActiveView(timer: timer)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: timer.state == .idle)
        .timerFinishShake(trigger: timer.finishCount)
        // Per-second ticks only while this seconds-precise view is on screen (see TimerTickPolicy).
        .onAppear { timer.isDetailVisible = true }
        .onDisappear { timer.isDetailVisible = false }
    }
}

// MARK: - Idle

private struct TimerIdleView: View {
    @Bindable var timer: TimerService

    private static let chipColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(String(localized: "Hızlı zamanlayıcı"))
                presetChips
                customRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            pomodoroCard
                .frame(width: 190)
        }
    }

    private var presetChips: some View {
        HStack(spacing: 8) {
            ForEach(TimerService.presets, id: \.self) { duration in
                Button {
                    timer.start(duration: duration)
                } label: {
                    VStack(spacing: 0) {
                        Text("\(Int(duration / 60))")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("dk")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(TimerPressableStyle(shape: AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))))
                .help("\(TimerFormatter.minutesLabel(duration)) zamanlayıcı başlat")
            }
        }
    }

    private var customRow: some View {
        HStack(spacing: 8) {
            Text("Özel")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Dakika", value: $timer.customMinutes, format: .number)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .onSubmit { timer.startCustom() }
            Stepper("Dakika", value: $timer.customMinutes, in: TimerService.customMinutesRange)
                .labelsHidden()
            Text("dk")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                timer.startCustom()
            } label: {
                Label("Başlat", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
            }
            .buttonStyle(TimerPressableStyle(isProminent: true, shape: AnyShape(Capsule())))
            .help("\(timer.customMinutes) dk zamanlayıcı başlat")
        }
    }

    private var pomodoroCard: some View {
        Button {
            timer.startPomodoro()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: TimerPhase.work.systemImage)
                        .foregroundStyle(TimerPhase.work.tint)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.title3)
                Spacer(minLength: 0)
                Text("Pomodoro")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(pomodoroSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                TimerSessionDots(completed: 0, total: timer.pomodoroSettings.sessionsBeforeLongBreak, tint: TimerPhase.work.tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(TimerPressableStyle(shape: AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))))
        .help("Pomodoro döngüsü başlat")
    }

    private var pomodoroSummary: String {
        let settings = timer.pomodoroSettings
        return String(localized: "\(settings.workMinutes) dk odak · \(settings.shortBreakMinutes) dk mola · \(settings.longBreakMinutes) dk uzun")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Running / paused / finished

private struct TimerActiveView: View {
    let timer: TimerService

    private static let ringSize: CGFloat = 118
    private static let ringLineWidth: CGFloat = 8

    private var phase: TimerPhase { timer.state.phase ?? .countdown }

    var body: some View {
        HStack(spacing: 24) {
            ring
            VStack(alignment: .leading, spacing: 6) {
                header
                countdown
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ring: some View {
        ZStack {
            TimerProgressRing(progress: timer.progress, tint: phase.tint, lineWidth: Self.ringLineWidth)
            VStack(spacing: 4) {
                Image(systemName: timer.state.isFinished ? "checkmark" : phase.systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(phase.tint)
                    .contentTransition(.symbolEffect(.replace))
                Text("\(Int((timer.progress * 100).rounded()))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(phase.title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(phase.tint)
            if timer.isPomodoro {
                TimerSessionDots(
                    completed: timer.completedSessionsInCycle,
                    total: timer.sessionsBeforeLongBreak,
                    tint: TimerPhase.work.tint
                )
            }
            Spacer(minLength: 0)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var countdown: some View {
        Text(TimerFormatter.clock(timer.remaining))
            .font(.system(size: 52, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: TimerFormatter.clock(timer.remaining))
            .opacity(timer.state.isPaused ? 0.5 : 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var statusText: String {
        switch timer.state {
        case .paused: return String(localized: "Duraklatıldı")
        case .finished: return timer.upcomingPhase.map { String(localized: "Sıradaki: \($0.title)") } ?? String(localized: "Bitti")
        case .running, .idle: return timer.upcomingPhase.map { String(localized: "Sonraki: \($0.title)") } ?? ""
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch timer.state {
            case .running:
                TimerControlButton(systemImage: "pause.fill", help: String(localized: "Duraklat"), isProminent: true) { timer.pause() }
            case .paused:
                TimerControlButton(systemImage: "play.fill", help: String(localized: "Devam"), isProminent: true) { timer.resume() }
            case .finished:
                finishedPrimaryButton
            case .idle:
                EmptyView()
            }
            if timer.isPomodoro && !timer.state.isFinished {
                TimerControlButton(systemImage: "forward.end.fill", help: skipHelp) {
                    timer.skipPhase()
                }
            }
            TimerControlButton(systemImage: "xmark", help: cancelHelp) {
                timer.cancel()
            }
        }
    }

    private var skipHelp: String {
        let next = timer.upcomingPhase?.title ?? String(localized: "sonraki aşama")
        return String(localized: "Atla: \(next)")
    }

    private var cancelHelp: String {
        timer.state.isFinished ? String(localized: "Kapat") : String(localized: "İptal")
    }

    @ViewBuilder
    private var finishedPrimaryButton: some View {
        if let next = timer.upcomingPhase {
            TimerControlButton(systemImage: "play.fill", help: String(localized: "\(next.title) başlat"), isProminent: true) {
                timer.startNextPhase()
            }
        } else {
            TimerControlButton(systemImage: "arrow.counterclockwise", help: String(localized: "Yeniden başlat"), isProminent: true) {
                timer.start(duration: timer.phaseDuration)
            }
        }
    }
}
