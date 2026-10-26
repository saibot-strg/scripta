import Observation

/// Whether the dictation pill is shown; the view animates the change.
@MainActor
@Observable
final class HUDPresentation {
    var isShown = false
}
