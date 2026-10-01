import SwiftUI
import FocusCountCore

/// Observable replacement for AppStorage, with all values stored inside the data directory.
@propertyWrapper struct DirectoryPreference: DynamicProperty {
    @ObservedObject private var storage = FilePreferences.shared
    private let key: String
    private let fallback: Bool
    init(wrappedValue: Bool, _ key: String) { self.key = key; fallback = wrappedValue }
    var wrappedValue: Bool {
        get { storage.object(forKey: key) == nil ? fallback : storage.bool(forKey: key) }
        nonmutating set { storage.set(newValue, forKey: key) }
    }
    var projectedValue: Binding<Bool> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}
