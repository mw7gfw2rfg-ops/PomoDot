import AVFoundation
import GlassKit
import Foundation

/// The cues the app can play. One per meaningful event — nothing fires on hover, focus, or
/// mere state observation, because over-feedback trains you to ignore all of it
/// (apple-design § 13, "utility").
public enum Cue: Sendable, CaseIterable {
    case start
    case pause
    case skip
    case reset
    case focusEnded
    case breakEnded

    /// Each cue is a short sequence of (frequency in Hz, duration in seconds).
    ///
    /// Tuned as an instrument, not as notifications: transport cues are terse and low-key so
    /// they can fire many times an hour without wearing out, while the two phase-end cues are
    /// longer three-note figures because they're the only ones that must carry across a room.
    /// Rising = beginning, falling = stopping, which is the one bit of semantics a blip can
    /// reliably carry.
    var notes: [(frequency: Double, seconds: Double)] {
        switch self {
        case .start:      [(660, 0.045), (988, 0.055)]                    // rising: go
        case .pause:      [(494, 0.070)]                                  // single: held
        case .skip:       [(880, 0.028)]                                  // tick: dismissed
        case .reset:      [(660, 0.040), (440, 0.060)]                    // falling: wound back
        case .focusEnded: [(880, 0.090), (1108, 0.090), (1318, 0.170)]    // rising: earned
        case .breakEnded: [(1108, 0.080), (988, 0.080), (880, 0.150)]     // falling: back to it
        }
    }

    /// Phase-end cues are the ones you might be across the room from.
    var gain: Double {
        switch self {
        case .focusEnded, .breakEnded: 0.24
        default: 0.13
        }
    }
}

/// Synthesises and plays the cues.
///
/// Tones are generated at runtime rather than bundled as audio files, for the same reason the
/// dot-matrix is drawn rather than shipped as a font: the project's premise is that its assets
/// are generated. It also means the cue set is tunable by editing two numbers, and the app
/// carries no binary blobs.
@MainActor
public final class SoundEngine {

    public var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: SoundEngine.muteKey)
            // Muting should also stop the engine, not just skip playback — an idle audio
            // engine keeps an output device awake for no reason (ISC-47).
            if isMuted { stopEngine() }
        }
    }

    // nonisolated: referenced from default argument values and from the synthesis functions,
    // which deliberately stay off the main actor so they're testable without an audio device.
    nonisolated public static let muteKey = "soundMuted"
    nonisolated public static let sampleRate: Double = 44_100

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    /// Cues are generated once and reused; regenerating a buffer per press would be wasteful
    /// and would make rapid presses audibly inconsistent.
    private var cache: [Cue: AVAudioPCMBuffer] = [:]

    public init(isMuted: Bool = UserDefaults.standard.bool(forKey: SoundEngine.muteKey)) {
        self.isMuted = isMuted
    }

    // MARK: - Playback

    public func play(_ cue: Cue) {
        guard !isMuted else { return }
        // Audio is a nicety; the timer is the product. Every failure path here is silent by
        // design — a machine with no output device must still run a Pomodoro (ISC-48).
        guard let player = ensureEngineRunning() else { return }
        guard let buffer = buffer(for: cue) else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func ensureEngineRunning() -> AVAudioPlayerNode? {
        if let engine, let player, engine.isRunning { return player }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                         channels: 1) else { return nil }
        engine.attach(player)
        // ponytail: `connect(_:to:format:)` and `AVAudioPlayerNode.play()` are both
        // deprecated as of macOS 27. They don't warn here only because the package deploys
        // to macOS 26 — verified by compiling the same calls in a script with no deployment
        // target, which does warn. Raising the target will surface both; migrate then.
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            // No output device, or the engine refused to start. Give up quietly.
            return nil
        }

        self.engine = engine
        self.player = player
        return player
    }

    private func stopEngine() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private func buffer(for cue: Cue) -> AVAudioPCMBuffer? {
        if let cached = cache[cue] { return cached }
        guard let built = SoundEngine.makeBuffer(for: cue) else { return nil }
        cache[cue] = built
        return built
    }

    // MARK: - Synthesis

    /// Renders a cue's note sequence into a mono PCM buffer.
    nonisolated public static func makeBuffer(for cue: Cue, sampleRate: Double = SoundEngine.sampleRate) -> AVAudioPCMBuffer? {
        let samples = render(cue: cue, sampleRate: sampleRate)
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for (index, value) in samples.enumerated() { channel[index] = Float(value) }
        }
        return buffer
    }

    /// The actual synthesis, kept separate from `AVAudioPCMBuffer` so it can be unit-tested
    /// without an audio device.
    ///
    /// Sine plus a quiet third harmonic: a pure sine reads as a medical device, and the extra
    /// partial gives it the slight hardware edge the Teenage Engineering reference wants
    /// without tipping into chiptune.
    nonisolated public static func render(cue: Cue, sampleRate: Double = SoundEngine.sampleRate) -> [Double] {
        var samples: [Double] = []

        for note in cue.notes {
            let frameCount = Int(note.seconds * sampleRate)
            guard frameCount > 1 else { continue }

            for frame in 0..<frameCount {
                let t = Double(frame) / sampleRate
                // Denominator is frameCount - 1 so `progress` actually reaches 1.0 on the
                // final sample. Dividing by frameCount leaves the last sample mid-decay at
                // a non-zero amplitude — a step discontinuity, i.e. the click the envelope
                // exists to remove. Caught by `everyCueStartsAndEndsSilent`.
                let progress = Double(frame) / Double(frameCount - 1)
                let angular = 2 * Double.pi * note.frequency * t

                let tone = sin(angular) + 0.18 * sin(3 * angular)
                samples.append(tone * envelope(progress) * cue.gain)
            }
        }
        return samples
    }

    /// Fast attack, exponential decay, forced to exactly zero at both ends.
    ///
    /// The zero endpoints are the whole point: a waveform that starts or stops mid-cycle
    /// produces a step discontinuity, which is heard as a click on every single press
    /// (ISC-44). This is the difference between a cue that feels like hardware and one that
    /// feels broken.
    nonisolated static func envelope(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        let attack = 0.06
        if progress < attack { return progress / attack }
        let decayProgress = (progress - attack) / (1 - attack)
        return exp(-4.5 * decayProgress) * (1 - decayProgress)
    }
}
