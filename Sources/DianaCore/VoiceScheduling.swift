import Foundation

public enum VoiceScheduleError: Error, LocalizedError, Equatable {
    case missingTime, ambiguousTime, missingTitle, pastDate, unsupported
    public var errorDescription: String? {
        switch self {
        case .missingTime: "What day and time should I use? For example, tomorrow at 5 PM."
        case .ambiguousTime: "Is that AM or PM? Please say the time with AM or PM."
        case .missingTitle: "What should I call the reminder?"
        case .pastDate: "That time has already passed. What future day and time should I use?"
        case .unsupported:
            "I can save one-time reminders for today, tomorrow, a weekday, or in a number of minutes. Please include a clear time with AM or PM."
        }
    }
}

public enum VoiceScheduleParser {
    public static func wakeSuffix(in text: String) -> String? {
        guard
            let range = text.range(
                of: #"\b(?:hey|hi|hello)[,\s]+(?:diana|deanna)\b"#,
                options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(text[range.upperBound...]).trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    public static func isFarewell(_ text: String) -> Bool {
        let value = normalizedAnswer(text)
        let phrases: Set<String> = [
            "bye", "bye bye", "goodbye", "good bye", "see you", "see you later", "that's all", "that is all",
            "you can go", "go away", "thanks bye", "thank you bye",
        ]
        if phrases.contains(value) { return true }
        for name in ["diana", "deanna"] {
            if value.hasSuffix(" " + name), phrases.contains(String(value.dropLast(name.count + 1))) {
                return true
            }
        }
        return false
    }
    public static func endsWithFarewell(_ text: String) -> Bool {
        if isFarewell(text) { return true }
        return normalizedAnswer(text).range(
            of: #"\b(?:bye(?: bye)?|goodbye|good bye)(?: (?:diana|deanna))?$"#, options: .regularExpression)
            != nil
    }
    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) throws -> Reminder {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw VoiceScheduleError.missingTitle }
        var normalized = raw.lowercased().replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(
            of: "p.m.", with: "pm")
        let numbers = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
            "forty-five": 45, "forty five": 45, "sixty": 60,
        ]
        for (word, value) in numbers.sorted(by: { $0.key.count > $1.key.count }) {
            normalized = replace(
                "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", in: normalized,
                with: String(value))
        }
        if !matches(#"\b\d{1,4}[-/]\d{1,2}(?:[-/]\d{1,4})?\b"#, in: normalized).isEmpty {
            throw VoiceScheduleError.unsupported
        }
        if matches(
            #"\b(?:every|daily|weekly|monthly|next week|next month|january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
            in: normalized
        ).count > 0 {
            throw VoiceScheduleError.unsupported
        }
        let relativePattern = #"\bin\s+(\d{1,3})\s+(minutes?|hours?)\b"#
        let clockPattern =
            #"\b(?:at\s+)?(\d{1,2})(?:(?::|\s+)(\d{2}))?\s*(?:o'clock\s*)?(a\s*m|p\s*m)\b|\b(?:at\s+)?(\d{1,2}):(\d{2})\b|\b(noon|midnight)\b"#
        let datePattern =
            #"\b(?:today|tomorrow|(?:this|next)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        var due: Date
        var removing: [NSRange] = []
        let relative = matches(relativePattern, in: normalized).last
        let clocks = matches(clockPattern, in: normalized)
        let dates = matches(datePattern, in: normalized)
        if clocks.count > 1 && matches(#"\b(?:change|instead|actually|make it)\b"#, in: normalized).isEmpty {
            throw VoiceScheduleError.unsupported
        }
        if !matches(
            #"\b(?:yesterday|last week|tonight|this evening|this afternoon|this morning)\b"#, in: normalized
        ).isEmpty {
            throw VoiceScheduleError.unsupported
        }
        removing =
            clocks.map(\.range) + dates.map(\.range) + matches(relativePattern, in: normalized).map(\.range)
        if let relative, (clocks.last?.range.location ?? -1) < relative.range.location {
            let amount = Int(capture(1, relative, normalized)) ?? 0
            guard (1...720).contains(amount) else { throw VoiceScheduleError.unsupported }
            let minutes = capture(2, relative, normalized).hasPrefix("hour") ? amount * 60 : amount
            due = now.addingTimeInterval(Double(minutes * 60))
        } else if let clock = clocks.last {
            var hour = 0
            var minute = 0
            if !capture(1, clock, normalized).isEmpty {
                hour = Int(capture(1, clock, normalized)) ?? -1
                minute = Int(capture(2, clock, normalized)) ?? 0
                guard (1...12).contains(hour), (0...59).contains(minute) else {
                    throw VoiceScheduleError.missingTime
                }
                hour %= 12
                if capture(3, clock, normalized).replacingOccurrences(of: " ", with: "").hasPrefix("p") {
                    hour += 12
                }
            } else if !capture(4, clock, normalized).isEmpty {
                hour = Int(capture(4, clock, normalized)) ?? -1
                minute = Int(capture(5, clock, normalized)) ?? -1
                guard (0...23).contains(hour), (0...59).contains(minute) else {
                    throw VoiceScheduleError.missingTime
                }
                // Spoken "five thirty" / "5:30" still needs a meridiem.
                if (1...12).contains(hour) { throw VoiceScheduleError.ambiguousTime }
            } else {
                hour = capture(6, clock, normalized) == "noon" ? 12 : 0
            }
            let start = calendar.startOfDay(for: now)
            var day = start
            var explicitToday = false
            if let date = dates.last {
                let label = (normalized as NSString).substring(with: date.range)
                if label == "tomorrow" {
                    day = calendar.date(byAdding: .day, value: 1, to: start)!
                } else if label == "today" {
                    explicitToday = true
                } else {
                    let weekdays = [
                        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
                    ]
                    guard let index = weekdays.firstIndex(where: { label.hasSuffix($0) }) else {
                        throw VoiceScheduleError.unsupported
                    }
                    var offset = (index + 1 - calendar.component(.weekday, from: now) + 7) % 7
                    if label.hasPrefix("next ") && offset == 0 { offset = 7 }
                    day = calendar.date(byAdding: .day, value: offset, to: start)!
                }
            }
            guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                calendar.component(.hour, from: candidate) == hour
            else { throw VoiceScheduleError.missingTime }
            due = candidate
            if due <= now {
                if explicitToday
                    || dates.last.map({ (normalized as NSString).substring(with: $0.range) == "tomorrow" })
                        == true
                {
                    throw VoiceScheduleError.pastDate
                }
                due = calendar.date(byAdding: .day, value: dates.isEmpty ? 1 : 7, to: due)!
            }
        } else {
            if !matches(#"\bat\s+\d{1,2}(?:\s+o'clock)?\b"#, in: normalized).isEmpty {
                throw VoiceScheduleError.ambiguousTime
            }
            throw VoiceScheduleError.missingTime
        }
        var title = normalized as NSString
        for range in removing.sorted(by: { $0.location > $1.location }) {
            title = title.replacingCharacters(in: range, with: " ") as NSString
        }
        var cleaned = replace(
            #"^\s*(?:(?:can|could|would) you\s+)?(?:please\s+)?(?:schedule|set up|create|add|plan|remind me to|remind me about)\s+(?:(?:a|an|the)\s+)?"#,
            in: title as String, with: "")
        cleaned = replace(
            #"\b(?:please|instead|actually|change it to|make it|change the time to)\b"#, in: cleaned,
            with: " ")
        cleaned = replace(#"\s+"#, in: cleaned, with: " ").trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters))
        cleaned = replace(#"(?:\s+\b(?:on|for|at|to)\b)+$"#, in: cleaned, with: "")
        guard !cleaned.isEmpty, cleaned.count <= 160 else { throw VoiceScheduleError.missingTitle }
        cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        return Reminder(
            title: cleaned, kind: cleaned.localizedCaseInsensitiveContains("meeting") ? .meeting : .task,
            startsAt: due, createdAt: now)
    }
    public static func normalizedAnswer(_ text: String) -> String {
        replace(
            #"[^\p{L}\p{N}' ]"#, in: text.lowercased().replacingOccurrences(of: "’", with: "'"), with: " "
        ).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(
            of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).matches(
            in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }
    private static func capture(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : (text as NSString).substring(with: range)
    }
}

public enum VoiceConversationPhase: Sendable { case idle, requesting, confirming, saving }
public enum VoiceConversationAction: Equatable, Sendable {
    case prompt(String)
    case commit(Reminder)
    case finish(String)
    case ignore
}

public struct VoiceConversation: Sendable {
    public private(set) var phase: VoiceConversationPhase = .idle
    public private(set) var draft: Reminder?
    private var request = ""
    private var draftedAt: Date?
    private var warnedConflictIDs: Set<String> = []
    public private(set) var approvedConflictIDs: Set<String> = []
    public init() {}
    public mutating func wake() -> VoiceConversationAction {
        phase = .requesting
        draft = nil
        request = ""
        draftedAt = nil
        warnedConflictIDs = []
        approvedConflictIDs = []
        return .prompt("Yep, how can I help you?")
    }
    public mutating func cancel() {
        phase = .idle
        draft = nil
        request = ""
        draftedAt = nil
        warnedConflictIDs = []
        approvedConflictIDs = []
    }
    public mutating func receive(
        _ text: String, now: Date, calendar: Calendar = .current, schedules: AppData = AppData()
    ) -> VoiceConversationAction {
        let answer = VoiceScheduleParser.normalizedAnswer(text)
        guard phase != .idle && phase != .saving else { return .ignore }
        if VoiceScheduleParser.isFarewell(text) {
            cancel()
            return .finish("Bye. See you soon.")
        }
        if ["cancel", "never mind", "nevermind", "stop", "no", "nope", "don't save", "do not save"].contains(
            answer)
        {
            cancel()
            return .finish("Okay, nothing was saved.")
        }
        if phase == .confirming {
            guard let draft, let draftedAt, now.timeIntervalSince(draftedAt) < 120, draft.startsAt > now
            else {
                cancel()
                return .finish("That confirmation expired. Nothing was saved. Say hey Diana to start again.")
            }
            let approvals = [
                "yes", "yep", "yeah", "yes please", "yes save it", "yes schedule it", "save it", "confirm",
                "i confirm", "go ahead", "that's correct", "that is correct", "correct", "yes that's correct",
            ]
            let conflicts = ScheduleConflicts.find(for: draft, in: schedules, calendar: calendar)
            let currentIDs = Set(conflicts.map(\.id))
            if !currentIDs.isSubset(of: warnedConflictIDs) {
                warnedConflictIDs = currentIDs
                return .prompt(ScheduleConflicts.warning(conflicts))
            }
            let overrides = ["save anyway", "yes save anyway", "schedule anyway", "yes schedule anyway"]
            if overrides.contains(answer) || (conflicts.isEmpty && approvals.contains(answer)) {
                approvedConflictIDs = currentIDs
                phase = .saving
                return .commit(draft)
            }
            if !conflicts.isEmpty && approvals.contains(answer) {
                return .prompt(ScheduleConflicts.warning(conflicts))
            }
            let hasNewTime =
                text.range(
                    of:
                        #"\b(?:\d{1,2}\s*(?:a\.?m|p\.?m)|\d{1,2}:\d{2}|tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
            if hasNewTime || answer.contains("change") || answer.contains("instead")
                || answer.hasPrefix("actually") || answer.hasPrefix("make it") || answer.hasPrefix("no ")
            {
                let correction = text.replacingOccurrences(
                    of: #"^(?:yes[, ]*|no[, ]*|actually[, ]*)"#, with: "",
                    options: [.regularExpression, .caseInsensitive])
                return propose(
                    request + " change it to " + correction, now: now, calendar: calendar,
                    schedules: schedules)
            }
            if !conflicts.isEmpty { return .prompt(ScheduleConflicts.warning(conflicts)) }
            return .prompt("Please say yes to save the reminder, change the time, or say cancel.")
        }
        return propose(
            request.isEmpty ? text : request + " " + text, now: now, calendar: calendar, schedules: schedules)
    }
    private mutating func propose(_ text: String, now: Date, calendar: Calendar, schedules: AppData)
        -> VoiceConversationAction
    {
        request = text
        do {
            let value = try VoiceScheduleParser.parse(text, now: now, calendar: calendar)
            draft = value
            draftedAt = now
            phase = .confirming
            approvedConflictIDs = []
            let conflicts = ScheduleConflicts.find(for: value, in: schedules, calendar: calendar)
            warnedConflictIDs = Set(conflicts.map(\.id))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
            let summary = "Save a reminder for \(value.title), \(formatter.string(from: value.startsAt))?"
            return .prompt(
                summary + " "
                    + (conflicts.isEmpty
                        ? "Please say yes to save it, or cancel." : ScheduleConflicts.warning(conflicts)))
        } catch {
            phase = .requesting
            draft = nil
            return .prompt(
                (error as? VoiceScheduleError)?.errorDescription
                    ?? "Please tell me the reminder and its time again.")
        }
    }
}
