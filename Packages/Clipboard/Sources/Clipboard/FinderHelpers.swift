import Foundation

/// A file name that is not taken yet: "Shot.png", then "Shot 2.png", and so on.
public func uniqueFileName(base: String, extension ext: String, exists: (String) -> Bool) -> String {
    var name = "\(base).\(ext)"
    var number = 2
    while exists(name) {
        name = "\(base) \(number).\(ext)"
        number += 1
    }
    return name
}

/// The file name for an image dropped into a folder, stamped with the time it was saved.
public func clipboardImageName(now: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Clipboard \(formatter.string(from: now))"
}
