import Foundation

/// The days of a month laid out in weeks, starting on the calendar's first weekday. Nil
/// marks the empty cells before the first day.
public func monthGrid(for date: Date, calendar: Calendar = .current) -> [Date?] {
    guard let interval = calendar.dateInterval(of: .month, for: date),
          let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
    let weekday = calendar.component(.weekday, from: interval.start)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    let dates = days.compactMap { day in calendar.date(byAdding: .day, value: day - 1, to: interval.start) }
    return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
}

/// The weekday initials in the order the grid uses.
public func weekdaySymbols(calendar: Calendar = .current) -> [String] {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let first = calendar.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first])
}
