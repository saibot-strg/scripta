extension Dictionary {
    /// Like `subscript(_:default:)`, but usable in key paths and bindings
    /// (`$names[id, fallback: "Ich"]`): the fallback is a value, not a closure.
    subscript(key: Key, fallback fallback: Value) -> Value {
        get { self[key] ?? fallback }
        set { self[key] = newValue }
    }
}
