extension Optional {
    /// For `alert(_:isPresented:presenting:)` and `confirmationDialog`:
    /// `$item.isPresent` is true while there is a value, and dismissing the
    /// dialog sets the value back to nil. (The `item:` overloads that do this
    /// directly need Xcode 27; the release builds with Xcode 26.)
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}
