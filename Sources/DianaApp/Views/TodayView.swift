import DianaCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @State private var calendarVisible = false
    private var week: [Date] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: model.selectedDate)
        let monday = cal.date(
            byAdding: .day, value: -((weekday + 5) % 7), to: cal.startOfDay(for: model.selectedDate))!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                Text(model.selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(
                    .system(size: 12)
                ).foregroundStyle(theme.muted)
                Text(
                    Calendar.current.isDateInToday(model.selectedDate)
                        ? "Today, at your pace." : "Your day, at your pace."
                ).font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text("A little structure. A little space for yourself.").font(.system(size: 13))
                    .foregroundStyle(theme.muted)
            }
            VStack(spacing: 16) {
                HStack {
                    Text(model.selectedDate.formatted(.dateTime.month(.wide).year())).font(
                        .system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Today") { model.selectedDate = .now }.font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                    Button {
                        calendarVisible.toggle()
                    } label: {
                        Image(systemName: "calendar").font(.system(size: 13))
                    }.buttonStyle(.plain).help("Choose a date").popover(isPresented: $calendarVisible) {
                        DatePicker(
                            "Choose date",
                            selection: Binding(
                                get: { model.selectedDate },
                                set: {
                                    model.selectedDate = $0
                                    calendarVisible = false
                                }), displayedComponents: .date
                        ).datePickerStyle(.graphical).padding(16).frame(width: 280)
                    }
                    Button {
                        moveWeek(-1)
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    }.buttonStyle(.plain).help("Previous week")
                    Button {
                        moveWeek(1)
                    } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }.buttonStyle(.plain).help("Next week")
                }.foregroundStyle(theme.muted)
                HStack(spacing: 8) {
                    ForEach(week, id: \.self) { date in
                        let selected = Calendar.current.isDate(date, inSameDayAs: model.selectedDate)
                        Button {
                            model.selectedDate = date
                        } label: {
                            VStack(spacing: 8) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(
                                    .system(size: 10, weight: .medium))
                                Text(date.formatted(.dateTime.day())).font(
                                    .system(size: 18, weight: .semibold))
                                Circle().fill(
                                    Calendar.current.isDateInToday(date)
                                        ? selected ? .white : theme.accent : .clear
                                ).frame(width: 4, height: 4)
                            }.frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(
                                selected ? .white : theme.muted
                            ).background(
                                selected ? theme.button : theme.surface,
                                in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(
                            date.formatted(date: .complete, time: .omitted)
                        ).accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }.padding(.top, 5)
            if model.data.reminders.isEmpty {
                welcome
            } else {
                HStack {
                    SectionTitle(title: "Your day", subtitle: daySummary)
                    Spacer()
                    Button {
                        model.showCompleted.toggle()
                    } label: {
                        Label(
                            model.showCompleted ? "Hide finished" : "Show finished",
                            systemImage: model.showCompleted ? "eye.slash" : "checkmark.circle")
                    }.font(.system(size: 11)).foregroundStyle(theme.muted).buttonStyle(.plain)
                }
                if Calendar.current.isDateInToday(model.selectedDate), !model.overdue.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Still on your mind").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                            theme.muted)
                        ForEach(model.overdue) { TaskRow(occurrence: $0) }
                    }
                }
                if model.visibleOccurrences.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: model.query.isEmpty ? "sun.horizon" : "magnifyingglass").font(
                            .system(size: 30, weight: .light)
                        ).foregroundStyle(theme.accent)
                        Text(model.query.isEmpty ? "A little breathing room." : "No reminders found.").font(
                            .system(size: 17, weight: .medium))
                        Text(
                            model.query.isEmpty
                                ? "Nothing else scheduled for this day."
                                : "Try another name or choose a different day."
                        ).font(.system(size: 12)).foregroundStyle(theme.muted)
                        if model.query.isEmpty {
                            Button("Add a reminder") { model.showEditor() }.buttonStyle(QuietButtonStyle())
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleOccurrences) { occurrence in
                            TaskRow(occurrence: occurrence)
                            if occurrence.id != model.visibleOccurrences.last?.id {
                                Rectangle().fill(theme.line.opacity(0.7)).frame(height: 1).padding(
                                    .leading, 37)
                            }
                        }
                    }
                }
                if !model.data.reminders.isEmpty { quickTemplates }
            }
            if model.notificationState != .authorized && model.notificationState != .provisional {
                notificationPrompt
            }
            HStack(spacing: 7) {
                Image(systemName: "heart").font(.system(size: 11))
                Text("Small steps count. You’re doing just fine.").font(.system(size: 11))
            }.foregroundStyle(theme.muted).padding(.top, 4)
        }
    }
    private var daySummary: String {
        let total = model.selectedDayOccurrences.count
        let done = model.completedToday
        return total == 0
            ? "Nothing scheduled yet."
            : done > 0
                ? "\(done) of \(total) reminders completed. Keep it gentle."
                : "\(total) gentle \(total == 1 ? "nudge" : "nudges") to keep you on track."
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "sparkles").font(.system(size: 25, weight: .light)).foregroundStyle(
                    theme.accent
                ).frame(width: 48, height: 48).background(
                    theme.paleAccent, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    Text("You don’t have to remember everything.").font(.system(size: 19, weight: .semibold))
                        .tracking(-0.3)
                    Text("Start with one reminder. Diana will be there for the gentle nudge.").font(
                        .system(size: 13)
                    ).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            quickTemplates
            Rectangle().fill(theme.line).frame(height: 1)
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.dashed").font(.system(size: 20, weight: .light))
                    .foregroundStyle(theme.muted)
                Text("Your first reminder is a good place to start.").font(.system(size: 12)).foregroundStyle(
                    theme.muted)
                Spacer()
            }.padding(.vertical, 30)
        }.padding(.vertical, 8)
    }
    private var quickTemplates: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { templateButtons }
            VStack(alignment: .leading, spacing: 8) { templateButtons }
        }
    }
    @ViewBuilder private var templateButtons: some View {
        Button {
            model.showEditor(kind: .water)
        } label: {
            Label("Drink water", systemImage: "drop")
        }.buttonStyle(QuietButtonStyle())
        Button {
            model.showEditor(kind: .meeting)
        } label: {
            Label("Plan a meeting", systemImage: "video")
        }.buttonStyle(QuietButtonStyle())
        Button {
            model.showEditor(kind: .rest)
        } label: {
            Label("Take a break", systemImage: "leaf")
        }.buttonStyle(QuietButtonStyle())
    }
    private var notificationPrompt: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge").font(.system(size: 17)).foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("A nudge, even when you’re elsewhere.").font(.system(size: 12, weight: .semibold))
                Text("Enable macOS notifications alongside your desktop companion.").font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                if model.notificationState == .denied {
                    Button("Open notification settings") { openNotificationSettings() }.font(
                        .system(size: 11, weight: .medium)
                    ).buttonStyle(.plain).foregroundStyle(theme.accent)
                } else {
                    Button("Enable notifications") { Task { await model.enableNotifications() } }.font(
                        .system(size: 11, weight: .medium)
                    ).buttonStyle(.plain).foregroundStyle(theme.accent)
                }
            }
            Spacer()
        }.padding(17).background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func moveWeek(_ delta: Int) {
        model.selectedDate = Calendar.current.date(byAdding: .day, value: delta * 7, to: model.selectedDate)!
    }
}

struct TaskRow: View {
    var occurrence: Occurrence
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @State private var hovering = false
    @State private var confirmDelete = false
    var body: some View {
        if let reminder = model.reminder(for: occurrence) {
            let record = model.data.records[occurrence.id]
            let done = record?.completedAt != nil
            HStack(spacing: 12) {
                Button {
                    model.complete(occurrence)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(
                        .system(size: 20, weight: .light)
                    ).foregroundStyle(done ? theme.success : theme.muted.opacity(0.8))
                }.buttonStyle(.plain).help(done ? "Mark incomplete" : "Mark complete").accessibilityLabel(
                    "\(done ? "Reopen" : "Complete") \(reminder.title)")
                Image(systemName: reminder.kind.symbol).font(.system(size: 16)).foregroundStyle(
                    theme.category(reminder.kind)
                ).frame(width: 34, height: 36).background(
                    theme.category(reminder.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    model.editor = reminder
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reminder.title).font(.system(size: 13, weight: .semibold)).strikethrough(done)
                            .foregroundStyle(done ? theme.muted : theme.ink).lineLimit(2)
                        HStack(spacing: 5) {
                            if let snoozed = record?.snoozedUntil, snoozed > model.now {
                                Image(systemName: "zzz")
                                Text("Snoozed until \(snoozed.formatted(date: .omitted, time: .shortened))")
                            } else if record?.dismissedAt != nil {
                                Text("Dismissed")
                            } else {
                                Text(reminder.notes.isEmpty ? reminder.repetitionLabel : reminder.notes)
                                    .lineLimit(1)
                            }
                            if model.hasConflict(occurrence) {
                                Label("Time conflict", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(theme.category(.meeting)).help(
                                        "Another reminder starts at this time")
                            }
                        }.font(.system(size: 11)).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(occurrence.dueAt.formatted(date: .omitted, time: .shortened)).font(
                        .system(size: 11, weight: .medium)
                    ).monospacedDigit().foregroundStyle(theme.ink)
                    if reminder.repeatRule != .once {
                        Image(systemName: "repeat").font(.system(size: 10)).foregroundStyle(theme.muted)
                    }
                }.frame(minWidth: 61, alignment: .trailing)
                Menu {
                    Button("Edit reminder") { model.editor = reminder }
                    Button("Snooze 10 minutes") { model.snooze(occurrence) }.disabled(done)
                    Button("Remind me now") { model.presentReminder(occurrence) }
                    Divider()
                    Button("Delete reminder…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 18, height: 24)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Reminder actions")
            }.padding(.vertical, 15).padding(.horizontal, 4).background(
                hovering ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: 9)
            ).onHover { hovering = $0 }.confirmationDialog(
                "Delete ‘\(reminder.title)’?", isPresented: $confirmDelete
            ) {
                Button("Delete reminder", role: .destructive) { model.removeReminder(reminder) }
            } message: {
                Text("This removes its future reminders and completion history.")
            }
        }
    }
}

func openNotificationSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
        NSWorkspace.shared.open(url)
    }
}
