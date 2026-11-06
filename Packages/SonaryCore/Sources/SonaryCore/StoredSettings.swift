import Foundation

/// Reads and writes settings that live as JSON in UserDefaults, without losing them when the
/// settings type changes between versions.
///
/// Swift's synthesized `Decodable` throws when a key is missing, even for a property with a
/// default value. A settings struct that gained a field in an update could therefore no longer
/// read what the previous version saved, and everything fell back to the defaults: snippets,
/// scratchpad text, mappings, all of it. Here a value that does not decode is repaired step by
/// step instead: a missing or unreadable field takes its default, an unreadable element of a
/// list is dropped, and everything else the user saved is kept.
public enum StoredSettings {
    /// The value stored under `key`, or `fallback` when there is none.
    public static func load<T: Codable>(_ type: T.Type, key: String, from defaults: UserDefaults,
                                        fallback: T) -> T {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return decode(type, from: data, fallback: fallback)
    }

    public static func save<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Decodes `data`, filling in from `fallback` whatever is missing or no longer readable.
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(T.self, from: data) { return value }
        guard let stored = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return fallback
        }
        let base = (try? JSONEncoder().encode(fallback))
            .flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
        var candidate = addingMissingKeys(to: stored, from: base)
        // Every pass fixes one problem; a settings struct has far fewer than this.
        for _ in 0..<256 {
            guard let json = try? JSONSerialization.data(withJSONObject: candidate, options: [.fragmentsAllowed]) else {
                return fallback
            }
            do {
                return try decoder.decode(T.self, from: json)
            } catch let error as DecodingError {
                guard let path = failingPath(of: error), !path.isEmpty,
                      let repaired = repair(candidate, at: path[...], base: base) else { return fallback }
                candidate = repaired
            } catch {
                return fallback
            }
        }
        return fallback
    }

    // MARK: - Repair

    /// Top-level keys the stored value lacks, taken from the defaults. Only the top level: one
    /// level down a dictionary can be an enum case with its payload, where adding a key would
    /// break it. Deeper gaps are filled one at a time by `repair`.
    private static func addingMissingKeys(to stored: Any, from base: Any?) -> Any {
        guard var object = stored as? [String: Any], let defaults = base as? [String: Any] else { return stored }
        for (key, value) in defaults where object[key] == nil {
            object[key] = value
        }
        return object
    }

    /// Where decoding stopped: the coding path, plus the missing key itself for `keyNotFound`.
    private static func failingPath(of error: DecodingError) -> [any CodingKey]? {
        if case let .keyNotFound(key, context) = error { return context.codingPath + [key] }
        if case let .typeMismatch(_, context) = error { return context.codingPath }
        if case let .valueNotFound(_, context) = error { return context.codingPath }
        if case let .dataCorrupted(context) = error { return context.codingPath }
        return nil
    }

    /// Fixes the value at `path` inside `value`. Returns nil when it cannot be fixed at this
    /// level, so the caller replaces or drops the whole thing that contains it.
    private static func repair(_ value: Any, at path: ArraySlice<any CodingKey>, base: Any?) -> Any? {
        guard let key = path.first else { return base }
        let rest = path.dropFirst()

        if var object = value as? [String: Any] {
            let name = key.stringValue
            let baseChild = (base as? [String: Any])?[name]
            if rest.isEmpty {
                if let baseChild {
                    object[name] = baseChild
                    return object
                }
                // No default to put back: maybe the field is optional and decodes once it is gone.
                // If it is required after all, the next pass ends up in the `nil` branch below.
                guard object[name] != nil else { return nil }
                object.removeValue(forKey: name)
                return object
            }
            if let child = object[name], let fixed = repair(child, at: rest, base: baseChild) {
                object[name] = fixed
                return object
            }
            guard let baseChild else { return nil }
            object[name] = baseChild
            return object
        }

        if var array = value as? [Any], let index = key.intValue, array.indices.contains(index) {
            // List defaults do not line up with the stored elements, so elements have no default:
            // one that cannot be fixed is dropped, the others stay.
            if !rest.isEmpty, let fixed = repair(array[index], at: rest, base: nil) {
                array[index] = fixed
            } else {
                array.remove(at: index)
            }
            return array
        }

        return nil
    }
}
