@preconcurrency import EventKit
import Observation

public struct CalendarItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var isAllDay: Bool
}

/// Today's remaining events. Access is asked for only when the calendar widget is turned on.
@MainActor
@Observable
public final class CalendarSource {
    public private(set) var items: [CalendarItem] = []
    public private(set) var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @ObservationIgnored private let store = EKEventStore()

    public init() {}

    public func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        hasAccess = granted
        refresh()
    }

    /// The events of one day, all of them, for browsing the month.
    public func events(on day: Date, calendar: Calendar = .current) -> [CalendarItem] {
        guard hasAccess, let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: calendar.startOfDay(for: day), end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "",
                                start: $0.startDate, isAllDay: $0.isAllDay) }
    }

    /// The days of a month that have something on, by their number in the month.
    public func eventDays(inMonthOf date: Date, calendar: Calendar = .current) -> Set<Int> {
        guard hasAccess, let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let predicate = store.predicateForEvents(withStart: month.start, end: month.end, calendars: nil)
        var days = Set<Int>()
        for event in store.events(matching: predicate) {
            var day = max(event.startDate, month.start)
            let last = min(event.endDate ?? event.startDate, month.end)
            while day < last || calendar.isDate(day, inSameDayAs: event.startDate) {
                days.insert(calendar.component(.day, from: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)),
                      next < last else { break }
                day = next
            }
        }
        return days
    }

    public func refresh() {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { items = []; return }
        let now = Date()
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        items = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { CalendarItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "",
                                start: $0.startDate, isAllDay: $0.isAllDay) }
    }
}
