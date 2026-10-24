import AppKit

/// Plays system sounds one after another, so several hosts never talk over each other.
@MainActor
final class SoundPlayer {
    private var tail: Task<Void, Never>?
    private var current: NSSound?
    /// Raised by `stop()`; queued and running sounds of an older epoch give up.
    private var epoch = 0

    func play(_ name: String, times: Int) {
        let previous = tail
        let startedIn = epoch
        tail = Task {
            await previous?.value
            for _ in 0..<max(1, times) {
                guard startedIn == epoch,
                      let sound = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
                else { return }
                current = sound
                sound.play()
                try? await Task.sleep(nanoseconds: UInt64((sound.duration + 0.15) * 1_000_000_000))
            }
        }
    }

    /// Silences the sound that is playing and drops everything that is still queued.
    func stop() {
        epoch += 1
        current?.stop()
        current = nil
    }
}
