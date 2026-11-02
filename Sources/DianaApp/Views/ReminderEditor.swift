import AppKit
import DianaCore
import SwiftUI

struct ReminderEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: Reminder
    @State private var showingConflict = false
    @State private var reviewedConflicts: [ScheduleConflict] = []
    @FocusState private var titleFocused: Bool
    init(initial: Reminder) { _reminder = State(initialValue: initial) }
    private var conflicts: [ScheduleConflict] { model.conflicts(for: reminder) }
    private var exists: Bool { model.data.reminders.contains { $0.id == reminder.id } }
    private var problem: String? {
        if let error = reminder.validationError { return error }
        if reminder.repeatRule == .once && reminder.isEnabled
            && reminder.startsAt.addingTimeInterval(-Double(reminder.leadMinutes * 60)) <= .now
        {
            return "Choose a future time, allowing for the reminder’s lead time."
        }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(exists ? "A little change of plan." : "Make a little room.").font(
                        .system(size: 24, weight: .semibold)
                    ).tracking(-0.5)
                    Text(
                        exists
                            ? "Update this reminder and its future schedule."
                            : "Tell Diana what matters and when to give you a nudge."
                    ).font(.system(size: 12)).foregroundStyle(theme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(
                        width: 26, height: 26
                    ).background(theme.surface, in: Circle())
                }.buttonStyle(.plain).help("Close editor")
            }.padding(26)
            Rectangle().fill(theme.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        ForEach(ReminderKind.allCases) { kind in
                            Button {
                                reminder.kind = kind
                            } label: {
                                Label(kind.title, systemImage: kind.symbol).font(
                                    .system(size: 12, weight: .medium)
                                ).frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(
                                    reminder.kind == kind ? theme.category(kind) : theme.muted
                                ).background(
                                    reminder.kind == kind
                                        ? theme.category(kind).opacity(0.10) : theme.surface,
                                    in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityAddTraits(
                                reminder.kind == kind ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("What’s the reminder?")
                        TextField(
                            "A meeting, a task, a moment for yourself…", text: $reminder.title,
                            prompt: Text("A meeting, a task, a moment for yourself…").foregroundStyle(
                                theme.muted)
                        ).textFieldStyle(.plain).font(.system(size: 15, weight: .medium)).focused(
                            $titleFocused
                        ).padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(
                                    titleFocused ? theme.accent.opacity(0.5) : theme.line, lineWidth: 1)
                            ).accessibilityIdentifier("reminderTitle")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("A little context", optional: true)
                        TextField(
                            "Notes, a meeting link, or a little encouragement", text: $reminder.notes,
                            prompt: Text("Notes, a meeting link, or a little encouragement").foregroundStyle(
                                theme.muted), axis: .vertical
                        ).lineLimit(2...4).textFieldStyle(.plain).font(.system(size: 12)).padding(12)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1)
                            ).accessibilityIdentifier("reminderNotes")
                    }
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(reminder.repeatRule == .interval ? "Start date" : "Date")
                            DatePicker("Date", selection: $reminder.startsAt, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.field).accessibilityLabel("Reminder date")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(reminder.repeatRule == .interval ? "Not before" : "Time")
                            DatePicker(
                                "Time", selection: $reminder.startsAt, displayedComponents: .hourAndMinute
                            ).labelsHidden().datePickerStyle(.field).accessibilityLabel("Reminder time")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !conflicts.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("This time is already in use", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(conflicts.prefix(3).map(\.title).joined(separator: ", ")).font(
                                .system(size: 12)
                            ).fixedSize(horizontal: false, vertical: true)
                            Text("Choose another time, or review the conflict when saving.").font(
                                .system(size: 11))
                        }.foregroundStyle(theme.category(.meeting)).frame(
                            maxWidth: .infinity, alignment: .leading
                        ).padding(14).background(
                            theme.category(.meeting).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Repeat")
                            Picker("Repeat", selection: $reminder.repeatRule) {
                                ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Give me a nudge")
                            Picker("Lead time", selection: $reminder.leadMinutes) {
                                ForEach([0, 5, 10, 15, 30, 60], id: \.self) {
                                    Text($0 == 0 ? "At the scheduled time" : "\($0) minutes before").tag($0)
                                }
                            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                        }
                    }
                    if reminder.repeatRule == .interval {
                        Surface(padding: 16) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Label("A healthy little rhythm", systemImage: "repeat").font(
                                        .system(size: 12, weight: .semibold))
                                    Spacer()
                                    Picker("Interval", selection: $reminder.intervalMinutes) {
                                        ForEach(
                                            [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 720],
                                            id: \.self
                                        ) { Text("Every \($0) min").tag($0) }
                                    }.labelsHidden().frame(width: 150)
                                }
                                HStack(spacing: 20) {
                                    DatePicker(
                                        "From", selection: windowTime(\.windowStart),
                                        displayedComponents: .hourAndMinute
                                    ).datePickerStyle(.field)
                                    DatePicker(
                                        "Until", selection: windowTime(\.windowEnd),
                                        displayedComponents: .hourAndMinute
                                    ).datePickerStyle(.field)
                                }.font(.system(size: 12))
                                Text(
                                    "Repeats within these active hours each day. The start date and “not before” time set the first possible occurrence."
                                ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                                    horizontal: false, vertical: true)
                            }
                        }
                    }
                    if exists {
                        Toggle("Reminder is active", isOn: $reminder.isEnabled).toggleStyle(.switch)
                            .controlSize(.small).font(.system(size: 12))
                    }
                    if let problem, !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 11))
                            .foregroundStyle(theme.category(.meeting)).fixedSize(
                                horizontal: false, vertical: true)
                    }
                }.padding(26)
            }.scrollIndicators(.hidden)
            Rectangle().fill(theme.line).frame(height: 1)
            HStack {
                Image(systemName: "sparkle").foregroundStyle(theme.accent)
                Text("Diana will take it from here.").font(.system(size: 11)).foregroundStyle(theme.muted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button(conflicts.isEmpty ? (exists ? "Save changes" : "Create reminder") : "Review conflict")
                {
                    let found = conflicts
                    if found.isEmpty {
                        model.saveReminder(reminder)
                    } else {
                        reviewedConflicts = found
                        showingConflict = true
                    }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(
                    problem != nil || model.storageFailure != nil
                ).accessibilityIdentifier("saveReminder")
            }.padding(22)
        }.frame(
            width: 570,
            height: min(
                reminder.repeatRule == .interval ? 765 : 665, (NSScreen.main?.visibleFrame.height ?? 900) - 90
            )
        ).background(theme.background).foregroundStyle(theme.ink).tint(theme.accent).onAppear {
            if reminder.title.isEmpty { titleFocused = true }
        }.confirmationDialog(
            "Another reminder starts at this time.", isPresented: $showingConflict, titleVisibility: .visible
        ) {
            Button("Save anyway") {
                model.saveReminder(reminder, approvedConflicts: Set(reviewedConflicts.map(\.id)))
            }
            Button("Choose another time", role: .cancel) {}
        } message: {
            Text(
                "This shares its start time with " + reviewedConflicts.map(\.title).joined(separator: ", ")
                    + ".")
        }
    }
    private func fieldLabel(_ text: String, optional: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 12, weight: .medium))
            if optional { Text("optional").font(.system(size: 10)).foregroundStyle(theme.muted) }
        }
    }
    private func windowTime(_ key: WritableKeyPath<Reminder, Int>) -> Binding<Date> {
        Binding(
            get: { ScheduleEngine.wallClock(minutes: reminder[keyPath: key], on: .now) ?? .now },
            set: {
                reminder[keyPath: key] =
                    Calendar.current.component(.hour, from: $0) * 60
                    + Calendar.current.component(.minute, from: $0)
            })
    }
}
