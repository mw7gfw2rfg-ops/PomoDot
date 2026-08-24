import Testing
import Foundation
@testable import PomoDotKit
import GlassKit

// MARK: - Sound synthesis
//
// Tests the sample generation, not playback — the synthesis is deliberately nonisolated and
// device-free so it can be asserted on in CI or on a machine with no audio output.

@Test
func everyCueGeneratesSamples() {
    // ISC-43.
    for cue in Cue.allCases {
        let samples = SoundEngine.render(cue: cue)
        #expect(!samples.isEmpty, "\(cue) produced no audio")
    }
}

@Test
func everyCueStartsAndEndsSilent() {
    // ISC-44/45. A waveform that begins or ends mid-cycle is a step discontinuity, which is
    // heard as a click on every single press. The envelope must pin both ends to zero.
    for cue in Cue.allCases {
        let samples = SoundEngine.render(cue: cue)
        #expect(abs(samples.first ?? 1) < 1e-9, "\(cue) starts with a click")
        #expect(abs(samples.last ?? 1) < 1e-9, "\(cue) ends with a click")
    }
}

@Test
func cuesNeverClip() {
    // Sample values outside ±1 wrap or distort in the output stage.
    for cue in Cue.allCases {
        let peak = SoundEngine.render(cue: cue).map(abs).max() ?? 0
        #expect(peak <= 1.0, "\(cue) clips at \(peak)")
        #expect(peak > 0.01, "\(cue) is effectively silent")
    }
}

@Test
func envelopeIsZeroAtBothEndsAndPositiveInside() {
    #expect(SoundEngine.envelope(0) == 0)
    #expect(SoundEngine.envelope(1) == 0)
    #expect(SoundEngine.envelope(0.5) > 0)
}

@Test
func cuesAreDistinguishableFromEachOther() {
    // Six events that all sounded the same would carry no information.
    let rendered = Cue.allCases.map { SoundEngine.render(cue: $0) }
    for i in rendered.indices {
        for j in rendered.indices where j > i {
            #expect(rendered[i] != rendered[j],
                    "\(Cue.allCases[i]) and \(Cue.allCases[j]) are identical")
        }
    }
}
