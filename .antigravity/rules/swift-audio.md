# Audio Engine Rules

- Always remove `addPeriodicTimeObserver` tokens when switching tracks or tearing down the player to prevent memory leaks.
- Ensure `MPRemoteCommandCenter` handles both `.skipForwardCommand` (30s) and `.skipBackwardCommand` (15s).
- Preserve user playback speed persistently (`UserDefaults` or SwiftData) across track transitions.
