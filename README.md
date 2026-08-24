# PomoDot

A Pomodoro timer that lives in the macOS menu bar, drawn as a dot-matrix display on a
sheet of genuinely transparent Liquid Glass.

Nothing's NDot lineage for the numerals — 5×7 rounded dots on a grid, unlit cells and all,
traced back to 1980s IBM mainframe displays. Teenage Engineering's discipline for everything
else — monospaced type exclusively, micro-caps legends, a 60-tick instrument ring, and a
single accent colour that exists only while you're actually focusing.

![the panel](docs/panel.png)

## Install

Requires macOS 26 or later (Liquid Glass is a macOS 26 API) and a Swift 6.2+ toolchain.

```bash
git clone <this repo> && cd PomoDot
./build.sh release
open build/PomoDot.app
```

To keep it around: `cp -R build/PomoDot.app /Applications/`.

There's no `.xcodeproj` — an `.app` is a directory with an `Info.plist`, and `build.sh`
assembles one from the SwiftPM product in about a dozen lines.

## Using it

Click the countdown in the menu bar to open the panel.

| Control | Does |
|---|---|
| **START / PAUSE** | Runs or holds the current phase |
| **SKIP** | Abandons this phase and moves to the next. A skipped focus earns no session pip |
| **RESET** | Returns the current phase to full length |
| **MIN 15 / 25 / 50** | Sets the focus length |
| **SND / MUTE** | Toggles the audio cues; persists across relaunch |
| **QUIT** | Quits |

Six synthesised cues — start, pause, skip, reset, focus-end, break-end. Rising figures for
beginnings, falling for stops. The two phase-end cues are longer and about twice the gain,
because they're the only ones you might be across the room from.

Below the transport, separated by a hairline, is the record: time focused today, over the
last 7 days, and in total, with a GitHub-style heatmap of the last 26 weeks underneath.
Intensity has five levels anchored to pomodoro counts (roughly one, two, four, six), so a
bright square always means the same amount of work regardless of how the rest of the window
went. History lives in `~/Library/Application Support/PomoDot/focus-log.jsonl`.

Cadence is the standard one: focus → short break, and every 4th *completed* focus earns a
long break. The four dashes under the dial are the session pips; they reset when you take
the long break.

When a phase ends the app plays a sound, pulses the menu bar item, and opens the panel.

## Design notes

Three decisions did most of the work.

**The unlit dots are load-bearing.** Rendering the whole 5×7 grid — dim cells and all — is
what makes it read as a dot-matrix *display* rather than a stylised font. It also does real
work: the dim grid is a local scrim, giving the lit dots a field to sit against, which is
what lets the panel use `Glass.clear` without a background plate behind the numerals. The
aesthetic choice and the legibility requirement turned out to be the same choice.

That argument does *not* survive at menu bar scale, and the build originally got this wrong.
At a 1.7pt dot the unlit cells sit too close to the lit ones to be told apart and the whole
block smears into a grey rectangle — and a template image has nothing to be legible
*against* anyway, because macOS guarantees its contrast. So the menu bar draws lit dots only.

A related trap, also tried and rejected: making the unlit cells a fixed *dark substrate*,
the way a physical matrix display has one. It reads well in theory and badly in practice —
over a mid-tone backdrop the dark cells contrast with the *backdrop*, so lit and unlit dots
compete and the digits collapse into noise. The rule that actually governs is that unlit
cells must sit close to the backdrop so only the lit ones pop, which is what deriving them
from the lit colour at low alpha does in either appearance.

**No text is ever the accent colour.** Over translucency the backdrop can be any colour, so
a fixed orange hue is a coin flip — orange text over a warm wallpaper simply disappears
(measured, over saturated test bands). Every label is `.primary`, which resolves against the
material. The accent lives in the status LED, the swept ticks, the progress arc, the pips
and the button strokes — marks that only have to be *noticed*, not *read*. This is also more
faithful to the references: Teenage Engineering colours the hardware, never the legends.

**The log records what you actually did, not what you meant to do.** A session logs the
minutes *actually* focused — paused time excluded, floored at 60 seconds — attributed to the
local calendar day it began. Logging only completed pomodoros would render 24 honest minutes
interrupted at the door as a blank day, and blank days for real work is what makes people
abandon a tracker. Logging the full 25 for a session abandoned at 3 would make the heatmap
flatter you, and a log that flatters you is one you stop trusting. Completed pomodoros still
drive the session pips; the log measures minutes. Two metrics, two questions.

The file is append-only JSONL opened with `O_APPEND`, which matters more than it sounds:
launching a new build before quitting the old one gives you two writers, and `seekToEnd` +
`write` caches a separate offset per handle, so they'd clobber each other rather than
interleave. Each record also stores its own `yyyy-MM-dd`, because bucketing purely at read
time means a DST change silently re-buckets history under you, and the original local day
can't be recovered from an epoch once the rule has changed.

**Time is read from a clock, never accumulated.** The engine stores an absolute deadline and
subtracts. A timer that decrements a counter stops being ticked while the process is
suspended and comes back having silently lost however long the lid was closed. As a
corollary the tick rate is irrelevant to correctness — the 1 Hz timer exists only to notice
the zero-crossing and prompt a redraw, and a missed tick self-corrects on the next one.

## Layout

```
Sources/PomoDotKit/     pure, testable core — state machine, glyph table, theme, views
  TimerEngine.swift     deadline-based pomodoro state machine
  DotMatrix.swift       5x7 glyph table and layout
  DotMatrixView.swift   SwiftUI dot renderer
  Theme.swift           colour, type and motion tokens
  Dial.swift            tick ring and session pips
  Controls.swift        transport buttons and preset chips
  PanelView.swift       the glass panel
  FocusLog.swift        append-only JSONL log of focused time
  SoundEngine.swift     runtime tone synthesis for the six cues
  Heatmap.swift         contribution grid + running totals
Sources/PomoDot/        AppKit shell
  PomoDotApp.swift      app delegate, status item, panel lifecycle
  GlassPanel.swift      the transparent NSPanel
  StatusItemRenderer.swift  Core Graphics template image for the menu bar
Tests/                  51 tests over the engine, log, cues and grid
ISA.md                  what "done" means for this project, as 73 testable criteria
```

Zero third-party dependencies, and no bundled assets of any kind — no fonts, no audio files.
`swift test` runs the suite.

## Known limits

- **No notification-centre alerts and no launch-at-login.** Both `UNUserNotificationCenter`
  and `SMAppService` need a signed, notarised bundle; from an ad-hoc build they fail
  silently, which is worse than not offering them. The sound-plus-pulse-plus-open-panel
  alert works on any build. `ponytail:` upgrade path — add both once signed with a
  Developer ID.
- Panel placement anchors to whichever screen actually contains the status item, which fixed
  a bug where it opened on the wrong monitor — but it hasn't been exercised across a live
  display unplug/replug while the panel is open.
- Break lengths aren't exposed in the UI yet (they persist, and the engine takes them).
- Reduce Motion and Reduce Transparency are read and branched on, but the toggles themselves
  haven't been exercised end-to-end (ISA follow-up `POMODOT-1`).
