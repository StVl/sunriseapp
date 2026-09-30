import SunriseCore
import SwiftUI

/// Bold value inside a secondary-colored line: "Starts at **07:00**".
private func labeled(_ label: String, _ value: String) -> Text {
    Text(label).foregroundColor(Theme.textSecondary)
        + Text(value).fontWeight(.semibold).foregroundColor(Theme.textPrimary)
}

private func hhmm(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return TimeText.hhmm(c.hour ?? 0, c.minute ?? 0)
}

private struct Divider: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
}

// MARK: - Glass panel: list ↔ editor (SPEC §6)

struct EditingPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            if state.draft != nil {
                AlarmEditor()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
            } else {
                AlarmList()
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
            }
        }
        .animation(Theme.sheet(0.45), value: state.draft?.id)
        .padding(EdgeInsets(top: 24, leading: 36, bottom: 22, trailing: 36))
        .frame(maxWidth: 480)
        .clipped()
        .glass(radius: 30)
    }
}

// MARK: - List

private struct AlarmList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Alarms").sectionLabel()
                TrialBadge()
                Spacer()
                Button { state.add() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(GhostButtonStyle(shape: AnyShape(Circle()), hoverOpacity: 0.12))
                .help("New alarm")
            }

            if state.alarms.isEmpty {
                Text("No alarms yet. Add one with +.")
                    .font(AppFont.make(14))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if state.alarms.count <= 5 {
                rows
            } else {
                // Five rows tall, then it scrolls.
                ScrollView(showsIndicators: false) { rows }
                    .frame(height: 5 * 64 + 4 * 8)
            }

            Divider()

            SpotifyButton()

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 30)) { tl in
                    VStack(alignment: .leading, spacing: 2) {
                        if let next = state.upcoming {
                            labeled(next.isSnooze ? "Snoozed until " : "Next: ", next.isSnooze ? hhmm(next.date) : AlarmSchedule.label(for: next.alarmDate, now: tl.date))
                            labeled("Light from ", next.isSnooze ? hhmm(next.date) : next.alarm.lightStartText)
                        } else {
                            Text("No alarms on").foregroundColor(Theme.textSecondary)
                        }
                    }
                    .font(AppFont.make(13))
                    .lineLimit(1)
                    .fixedSize()
                }
                Spacer(minLength: 8)
                Button("Go to sleep") { state.startSleepCountdown() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(state.upcoming == nil)
                    .opacity(state.upcoming == nil ? 0.5 : 1)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(state.alarms) { alarm in
                AlarmRow(alarm: alarm)
            }
        }
    }
}

private struct AlarmRow: View {
    @EnvironmentObject var state: AppState
    let alarm: Alarm
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Button { state.edit(alarm.id) } label: {
                HStack(alignment: .center, spacing: 14) {
                    Text(alarm.timeText)
                        .font(AppFont.make(34, .light))
                        .tracking(-0.34)
                        .foregroundColor(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alarm.daysLabel) · \(alarm.sunriseMinutes) min")
                            .font(AppFont.make(13, .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Light \(alarm.lightStartText) → \(alarm.fullLightText)")
                            .font(AppFont.make(12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(alarm.enabled ? 1 : 0.5)

            AlarmToggle(isOn: Binding(get: { alarm.enabled }, set: { state.setEnabled(alarm.id, $0) }))
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(hover ? 0.12 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeInOut(duration: 0.2), value: alarm.enabled)
    }
}

// MARK: - Editor

private struct AlarmEditor: View {
    @EnvironmentObject var state: AppState

    /// The draft, falling back to a default while the editor animates out.
    private var draft: Binding<Alarm> {
        Binding(get: { state.draft ?? Alarm() }, set: { state.draft = $0 })
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text(state.draftIsNew ? "New alarm" : "Edit alarm").sectionLabel()
                HStack {
                    Button { state.closeEditor() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text("Back").font(AppFont.make(14, .semibold))
                        }
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                    .buttonStyle(GhostButtonStyle(hoverOpacity: 0.12))
                    Spacer()
                    if !state.draftIsNew {
                        Button { state.deleteDraft() } label: {
                            Text("Delete")
                                .font(AppFont.make(14, .semibold))
                                .foregroundColor(Color(hex: 0xff9a7a))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                        }
                        .buttonStyle(GhostButtonStyle(hoverOpacity: 0.12))
                    }
                }
            }

            TimeWheel(hour: draft.hour, minute: draft.minute)
                // Fresh wheels for each alarm opened.
                .id(state.draft?.id)

            DaysPicker(days: draft.days)

            Divider()

            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sunrise to 100%")
                        .font(AppFont.make(15, .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("\(draft.wrappedValue.sunriseMinutes)")
                        .font(AppFont.make(22, .semibold))
                        .foregroundColor(Theme.textPrimary)
                        + Text(" min")
                        .font(AppFont.make(14))
                        .foregroundColor(Theme.textSecondary)
                }
                SunriseSlider(value: draft.sunriseMinutes)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    labeled("Light from ", draft.wrappedValue.lightStartText)
                    labeled("Full light at ", draft.wrappedValue.fullLightText)
                }
                .font(AppFont.make(13))
                .lineLimit(1)
                .fixedSize()
                Spacer(minLength: 8)
                Button(state.previewStart == nil ? "Preview" : "Stop") { state.togglePreview() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Save") { state.saveDraft() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Going to sleep

/// "Screen goes dark in 3" → "Night-night", shown between the list and night mode.
struct SleepToast: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { tl in
            let elapsed = state.sleepStart.map { tl.date.timeIntervalSince($0) } ?? 0
            let counting = elapsed < AppState.sleepCountdownSeconds
            let remaining = max(1, Int((AppState.sleepCountdownSeconds - elapsed).rounded(.up)))
            HStack(spacing: 14) {
                if counting {
                    HStack(spacing: 6) {
                        Text("Screen goes dark in")
                            .foregroundColor(Theme.textSecondary)
                        Text("\(remaining)")
                            .foregroundColor(Theme.textPrimary)
                            .fontWeight(.semibold)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.easeOut(duration: 0.25), value: remaining)
                            .frame(minWidth: 12)
                    }
                    Button("Cancel") { state.cancelSleepCountdown() }
                        .buttonStyle(PillButtonStyle(kind: .secondary, height: 32, fontSize: 13))
                        .keyboardShortcut(.cancelAction)
                } else {
                    Image(systemName: "moon.fill")
                        .foregroundColor(Theme.cream)
                        .transition(.scale.combined(with: .opacity))
                    Text("Night-night")
                        .foregroundColor(Theme.textPrimary)
                        .fontWeight(.semibold)
                        .transition(.opacity)
                }
            }
            .font(AppFont.make(15))
            .animation(.easeInOut(duration: 0.3), value: counting)
            .padding(.leading, 24)
            .padding(.trailing, counting ? 10 : 24)
            .frame(height: 52)
            .glass(radius: 26, shadowBlur: 60, shadowY: 20)
        }
    }
}

// MARK: - Night mode pill (SPEC §7)

struct ArmedPill: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let next = state.upcoming
        let alarm = next?.alarm ?? state.ringingAlarm
        HStack(spacing: 6) {
            Button { state.wake() } label: {
                HStack(spacing: 14) {
                    Text(next?.isSnooze == true ? hhmm(next!.date) : alarm.timeText)
                        .font(AppFont.make(32))
                        .tracking(-0.32)
                        .foregroundColor(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next?.isSnooze == true ? "Snoozed · \(alarm.sunriseMinutes) min" : "\(alarm.daysLabel) · \(alarm.sunriseMinutes) min")
                            .font(AppFont.make(13, .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Light from \(alarm.lightStartText)" + (state.spotifyLink.connected ? " · Spotify" : ""))
                            .font(AppFont.make(12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    Chevron()
                        .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 14, height: 9)
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .frame(height: 56)
            }
            .buttonStyle(GhostButtonStyle(shape: AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))))

            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 32)

            Button { state.turnOffUpcoming() } label: {
                CloseIcon().frame(width: 44, height: 44)
            }
            .buttonStyle(GhostButtonStyle(shape: AnyShape(Circle()), hoverOpacity: 0.12))
            .help("Turn this alarm off")
        }
        .padding(6)
        .glass(radius: 24, shadowBlur: 60, shadowY: 20)
    }
}

private struct CloseIcon: View {
    @Environment(\.ghostHover) private var hover

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 12, y: 12))
            p.move(to: CGPoint(x: 12, y: 0)); p.addLine(to: CGPoint(x: 0, y: 12))
        }
        .stroke(hover ? Color.white : Theme.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 12, height: 12)
    }
}

private struct Chevron: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 1, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + 1))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 1))
        return p
    }
}

// MARK: - Ringing (SPEC §8)

struct RingingCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 22) {
            Text("Good morning").sectionLabel()

            Text(state.ringingAlarm.timeText)
                .font(AppFont.make(96, .light))
                .tracking(-96 * 0.02)
                .foregroundColor(Theme.textPrimary)

            VStack(spacing: 12) {
                HStack {
                    Text("Sunrise in progress").foregroundColor(Theme.textSecondary)
                    Spacer()
                    labeled("Full light at ", state.ringingAlarm.fullLightText)
                }
                .font(AppFont.make(13))

                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    ProgressTrack(fraction: state.ringProgress(at: tl.date))
                }
            }

            HStack(spacing: 10) {
                Button("Snooze") { state.snooze() }
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 48, fontSize: 15, fullWidth: true))
                Button("Stop") { state.stop() }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 48, fontSize: 15, fullWidth: true))
            }
        }
        .padding(EdgeInsets(top: 32, leading: 32, bottom: 28, trailing: 32))
        .frame(maxWidth: 400)
        .glass(radius: 30)
    }
}
