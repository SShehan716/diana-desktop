public enum CompanionVisitPhase: String, Sendable {
    case hidden, entering, presenting, kissing, exiting
    public var showsBubble: Bool { self == .presenting }
    public var isVisible: Bool { self != .hidden }
}

public enum CompanionVisitIntent: Equatable, Sendable { case enter, depart, hide, keep }

extension CompanionVisitPhase {
    public func intent(hasContent: Bool, enabled: Bool) -> CompanionVisitIntent {
        guard enabled else { return .hide }
        if hasContent { return self == .hidden || self == .kissing || self == .exiting ? .enter : .keep }
        return self == .entering || self == .presenting ? .depart : (self == .hidden ? .hide : .keep)
    }
}
