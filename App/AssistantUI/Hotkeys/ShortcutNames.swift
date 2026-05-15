import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that summons the overlay.
    static let summon = Self("summon", default: .init(.space, modifiers: [.control]))

    /// Local hotkey (active only while overlay is key window) that enters crop mode.
    static let crop = Self("crop", default: .init(.c, modifiers: [.shift, .option]))
}
