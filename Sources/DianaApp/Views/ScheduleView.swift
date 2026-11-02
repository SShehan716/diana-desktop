import DianaCore
import SwiftUI

struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @State private var filter = "All"
    @State private var deleting: Reminder?
    private var reminders: [Reminder] {
        model.data.reminders.filter { reminder in
            let state = filter == "All" || (filter == "Active" ? reminder.isEnabled : !reminder.isEnabled)
            return state
                && (model.query.isEmpty || reminder.title.localizedCaseInsensitiveContains(model.query)
                    || reminder.notes.localizedCaseInsensitiveContains(model.query))
        }.sorted { $0.startsAt < $1.startsAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Your schedule.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text("Give the important things a little time and space.").font(.system(size: 13))
                    .foregroundStyle(theme.muted)
            }
            HStack {
                HStack(spacing: 5) {
                    ForEach(["All", "Active", "Paused"], id: \.self) { value in
                        Button {
                            filter = value
                        } label: {
                            Text(value).font(.system(size: 12, weight: .medium)).padding(.horizontal, 15)
                                .padding(.vertical, 8).foregroundStyle(
                                    filter == value ? theme.accent : theme.muted
                                ).background(
                                    filter == value ? theme.paleAccent : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Text("\(reminders.count) \(reminders.count == 1 ? "reminder" : "reminders")").font(
                    .system(size: 12)
                ).foregroundStyle(theme.muted)
            }
            if reminders.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 35, weight: .light))
                        .foregroundStyle(theme.accent)
                    Text(model.query.isEmpty ? "A fresh page for your plans." : "No matching reminders.")
                        .font(.system(size: 19, weight: .medium))
                    Text("Meetings, everyday tasks, and the breaks in between.").font(.system(size: 13))
                        .foregroundStyle(theme.muted)
                    Button("Create a reminder") { model.showEditor() }.buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 6)
                }.frame(maxWidth: .infinity).padding(.vertical, 85)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(reminders) { reminder in
                        scheduleRow(reminder)
                        if reminder.id != reminders.last?.id { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "repeat").font(.system(size: 16))
                Text("Recurring reminders keep going. Completing one occurrence leaves the next one ready.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(theme.muted).padding(.top, 8)
        }.confirmationDialog(
            "Delete this reminder?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete reminder", role: .destructive) {
                if let deleting { model.removeReminder(deleting) }
                deleting = nil
            }
        } message: {
            Text("This removes the reminder and all of its future occurrences.")
        }
    }
    private func scheduleRow(_ reminder: Reminder) -> some View {
        HStack(spacing: 15) {
            Image(systemName: reminder.kind.symbol).font(.system(size: 19)).foregroundStyle(
                theme.category(reminder.kind)
            ).frame(width: 44, height: 44).background(
                theme.category(reminder.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Button {
                model.editor = reminder
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(reminder.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(
                            theme.ink)
                        if !reminder.isEnabled {
                            Text("Paused").font(.system(size: 10)).foregroundStyle(theme.muted)
                        }
                    }
                    HStack(spacing: 9) {
                        Label(
                            reminder.repetitionLabel,
                            systemImage: reminder.repeatRule == .once ? "clock" : "repeat")
                        Text("·")
                        Text(
                            reminder.repeatRule == .interval
                                ? "\(time(reminder.windowStart))–\(time(reminder.windowEnd))"
                                : reminder.startsAt.formatted(date: .abbreviated, time: .shortened))
                    }.font(.system(size: 11)).foregroundStyle(theme.muted)
                    if !reminder.notes.isEmpty {
                        Text(reminder.notes).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Toggle(
                "Enable \(reminder.title)",
                isOn: Binding(get: { reminder.isEnabled }, set: { _ in model.toggleEnabled(reminder) })
            ).labelsHidden().toggleStyle(.switch).controlSize(.small)
            Menu {
                Button("Edit") { model.editor = reminder }
                Button(reminder.isEnabled ? "Pause" : "Resume") { model.toggleEnabled(reminder) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = reminder }
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Schedule actions")
        }.padding(.vertical, 21)
    }
    private func time(_ minutes: Int) -> String {
        let date = ScheduleEngine.wallClock(minutes: minutes, on: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
