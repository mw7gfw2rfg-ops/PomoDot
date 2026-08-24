---
task: Build PomoDot — a transparent Liquid Glass menu bar Pomodoro timer
project: PomoDot
effort: E3
phase: verify
progress: 72/73
mode: algorithm
started: 2026-08-24
updated: 2026-08-24
---

## Problem

Archie has no ambient way to run focused study blocks. Every existing macOS Pomodoro timer either (a) takes a Dock slot and a window, pulling attention away from the work it is supposed to protect, or (b) sits in the menu bar as an opaque, visually foreign chip that fights the system's own material language. None of them are pleasant enough to *want* to look at, so none of them get used. A timer that is unpleasant to glance at is a timer that gets ignored, and an ignored timer protects no study time.

## Vision

A dot-matrix countdown lives quietly in the menu bar, monochrome and template-tinted so it reads as though Apple shipped it. Click it and a pane of genuinely transparent Liquid Glass *materialises* underneath — blur and scale arriving together, not a rectangle fading in. Inside: enormous IBM-mainframe dot-matrix numerals where every dot in the 5×7 grid is visible and only the lit ones burn bright, a Teenage Engineering tick-ring, and micro-caps monospace legends. During focus a single orange accent exists; the moment the break starts the colour drains out of the interface entirely. Nothing is opaque. Nothing is decorative. The wallpaper shows through the whole thing.

## Out of Scope

No Dock icon, no main window, no menu bar menu of text items. No task lists, tagging, projects, statistics dashboards, streaks, or gamification — this counts down and it changes phase, nothing else. No cloud sync, no accounts, no network access of any kind. No third-party dependencies and no bundled font files; the dot-matrix is drawn geometrically and every other glyph is the system monospaced face. No iOS/iPadOS companion. No launch-at-login and no system notification-centre alerts in v1 (both require a signed, notarised bundle — deferred, see Decisions).

## Principles

- **The material is the design.** Transparency is not a skin over an opaque app; there is no opaque layer anywhere in the render tree to hide.
- **Restraint carries the meaning.** Colour is a signal, not decoration. If the accent is always present it signals nothing.
- **Monospace or dots — never proportional.** Teenage Engineering's typographic discipline is exclusivity; one proportional glyph breaks it.
- **Time is read from a clock, never accumulated.** Any timer that decrements a counter drifts and dies at system sleep.
- **Responsiveness precedes beauty.** Feedback on pointer-down; every animation interruptible from its presentation value.

## Constraints

- Swift 6.4 / SwiftUI + AppKit, targeting macOS 26+ (`Glass`, `glassEffect` are macOS 26 API). Host is macOS 27.0, SDK macosx27.0.
- Liquid Glass via the real SDK symbols only: `SwiftUICore.Glass` (`.clear`/`.regular`/`.tint`/`.interactive`) and `View.glassEffect(_:in:)`. No hand-rolled blur imitation.
- Zero external packages. Standard library, SwiftUI, AppKit, Foundation only.
- Must build from the command line with `swift build` — no `.xcodeproj` checked in.
- `LSUIElement = true`; the app must never appear in the Dock or the ⌘-Tab switcher.
- Panel background must be genuinely clear at the `NSWindow` level (`isOpaque = false`, `backgroundColor = .clear`), not merely dark-tinted.
- Must honour Reduce Motion and Reduce Transparency system settings.

## Goal

Ship a runnable, code-signed-optional `PomoDot.app` bundle that installs a template-rendered dot-matrix Pomodoro countdown in the macOS menu bar and opens a borderless, fully transparent Liquid Glass panel whose entire visual identity is drawn 5×7 dot-matrix numerals plus system-monospaced micro-caps, with a correct sleep-resilient focus/short-break/long-break state machine driven by monotonic-clock deadlines.

## Criteria

**Build & packaging**
- [x] ISC-1: `swift build -c release` exits 0 with no errors in `~/Developer/PomoDot`.
- [x] ISC-2: `swift build` emits zero warnings from first-party sources in `Sources/PomoDot`.
- [x] ISC-3: `Package.swift` declares zero entries in `dependencies:`.
- [x] ISC-4: A bundle exists at `~/Developer/PomoDot/build/PomoDot.app` with `Contents/MacOS/PomoDot` executable.
- [x] ISC-5: `Contents/Info.plist` contains `LSUIElement` = `true`.
- [x] ISC-6: `Contents/Info.plist` declares `LSMinimumSystemVersion` ≥ `26.0`.
- [x] ISC-7: `build.sh` regenerates the bundle end-to-end from a clean `build/` directory.
- [x] ISC-8: `lipo -archs` on the built binary reports `arm64`.

**Menu bar presence**
- [x] ISC-9: Launching the app creates exactly one `NSStatusItem` in the system status bar.
- [x] ISC-10: The status item image has `isTemplate == true` so macOS tints it for light/dark menu bars.
- [x] ISC-11: The status item label renders the remaining time as 5×7 dot-matrix glyphs, not as system text.
- [x] ISC-12: The status item redraws at least once per second while a phase is running.
- [x] ISC-13: Anti: the app does not appear in the Dock while running (`NSApp.activationPolicy == .accessory`).

**Liquid Glass panel**
- [x] ISC-14: The panel `NSWindow` reports `isOpaque == false` and `backgroundColor == NSColor.clear`.
- [x] ISC-15: The panel window's style mask includes `.borderless` and excludes `.titled`.
- [x] ISC-16: The SwiftUI source calls `.glassEffect(` with a `Glass` value on the panel's root container.
- [x] ISC-17: The panel uses `Glass.clear` (the transparent variant) as its default material.
- [x] ISC-18: Exactly one glass surface exists in the panel hierarchy — no `.glassEffect(` nested inside another.
- [x] ISC-19: The panel is positioned horizontally anchored to the status item's screen frame, not screen-centred.
- [x] ISC-20: The panel dismisses when the user clicks outside it.
- [x] ISC-21: Anti: no view in the panel sets an opaque background colour (no `Color.black`/`Color.white`/`.windowBackground` fills behind content).

**Dot-matrix typography (Nothing)**
- [x] ISC-22: A glyph table defines 5×7 bitmaps for all ten digits `0`–`9`.
- [x] ISC-23: A glyph exists for `:` so `MM:SS` renders entirely in dot-matrix.
- [x] ISC-24: Unlit grid positions render at reduced opacity rather than being omitted — the full matrix is visible.
- [x] ISC-25: Dots render as circles (`Circle`/`ellipse`), not squares — NDot is a rounded dot-matrix.
- [x] ISC-26: Anti: no `.ttf`/`.otf` font file is bundled or referenced anywhere in the repo.

**Monospace discipline (Teenage Engineering)**
- [x] ISC-27: Every non-dot-matrix text style in the app uses `design: .monospaced`.
- [x] ISC-28: Anti: no call to `.font(.system(size:weight:))` without `design: .monospaced` appears in panel source.
- [x] ISC-29: Micro-caps legends apply positive tracking (`.tracking(` with a value > 0).
- [x] ISC-30: A tick-ring renders 60 radial ticks with every 5th visually emphasised.

**Colour restraint**
- [x] ISC-31: Exactly one accent colour is defined for the focus phase.
- [x] ISC-32: The break phases resolve to a neutral (non-chromatic) accent — colour drains on break.

**Timer correctness**
- [x] ISC-33: Remaining time is computed from a stored `ContinuousClock.Instant` deadline, not by decrementing a counter each tick.
- [x] ISC-34: The state machine advances focus → short break → focus, and to a long break after every 4th focus.
- [x] ISC-35: Pausing stores remaining duration and resuming recomputes a fresh deadline.
- [x] ISC-36: A unit test asserts the 4th completed focus yields `.longBreak`.
- [x] ISC-37: A unit test asserts remaining time is derived from the deadline and is unaffected by tick frequency.
- [x] ISC-38: `swift test` exits 0.

**Sound (v1.1)**
- [x] ISC-42: A tone is synthesised at runtime — no `.aiff`/`.wav`/`.mp3`/`.caf` asset is bundled or referenced.
- [x] ISC-43: Distinct cues exist for start, pause, skip, reset, focus-end and break-end (6 distinct events).
- [x] ISC-44: Every generated buffer begins and ends at zero amplitude (envelope applied), so no cue clicks.
- [x] ISC-45: A unit test asserts the first and last samples of a generated cue are silent.
- [x] ISC-46: A mute control exists in the panel and its state persists across a relaunch.
- [x] ISC-47: Anti: when muted, no audio node is started and no cue plays.
- [x] ISC-48: Audio failure (no device, engine start error) never crashes or blocks the timer.

**Focus log (v1.1)**
- [x] ISC-49: Completed focus time is appended to a durable file outside the app bundle.
- [x] ISC-50: The store is append-only JSONL — one self-contained JSON object per line.
- [x] ISC-51: The log survives an app relaunch (write, quit, relaunch, read back).
- [x] ISC-52: Abandoning a focus phase (skip/reset) logs the time actually focused, not the full phase length.
- [x] ISC-53: Anti: paused time is never counted as focused time.
- [x] ISC-54: Anti: break phases are never written to the focus log.
- [x] ISC-55: Sessions shorter than a 60s floor are not logged, so stray taps don't create noise.
- [x] ISC-56: Daily totals bucket by the user's *local* calendar day, not by UTC.
- [x] ISC-57: A corrupt or partial line in the log is skipped, not fatal.
- [x] ISC-58: A unit test covers write → read → aggregate round-trip against a temp directory.
- [x] ISC-59: Anti: tests and screenshots never write to the real `~/Library/Application Support/PomoDot` log.

**Heatmap + stats (v1.1)**
- [x] ISC-60: The panel shows a total of time focused today.
- [x] ISC-61: The panel shows a rolling 7-day total and an all-time total.
- [x] ISC-62: Durations render as monospaced `Nh Nm`, consistent with the type rule.
- [x] ISC-63: A heatmap renders as a grid of 7 day-rows by N week-columns, GitHub-style.
- [x] ISC-64: Each column is one calendar week and rows are ordered by weekday.
- [x] ISC-65: The rightmost column is the current week — the grid ends at today.
- [x] ISC-66: Cell intensity has 5 discrete levels driven by minutes focused that day.
- [x] ISC-67: A `LESS … MORE` legend shows the scale, in micro-caps monospace.
- [x] ISC-68: The window length is stated in the UI so "a set length of time" is explicit.
- [x] ISC-69: Anti: the heatmap adds no second glass surface — ISC-18 still holds at exactly one.
- [x] ISC-70: Anti: heatmap cells are squares, not circles, so they never compete with the dot-matrix.
- [x] ISC-71: An empty log renders a deliberate empty grid, not a blank space or a crash.
- [x] ISC-72: A unit test asserts grid geometry — 7 rows, correct weekday alignment, today in the last column.
- [x] ISC-73: The panel still fits on screen below the status item after the new sections are added.

**Fluid interface (apple-design)**
- [x] ISC-39: Control press feedback is bound to the pressed state (pointer-down), not to the action closure.
- [x] ISC-40: Phase transitions animate with a spring, and the panel entrance animates blur/scale together.
- [DEFERRED-VERIFY] ISC-41: Antecedent: the app respects `accessibilityReduceMotion` and `accessibilityReduceTransparency`, so the aesthetic never costs legibility for a user who has asked the system for less.

## Test Strategy

| isc | type | check | threshold | tool |
|-----|------|-------|-----------|------|
| ISC-1,2,38 | build | compile + test exit status | exit 0 | `Bash: swift build/test` |
| ISC-3,26,28 | static | absence grep over repo | 0 matches | `Grep` |
| ISC-4..8 | artifact | bundle layout + plist keys + arch | present | `Bash: ls/plutil/lipo` |
| ISC-9..13 | runtime | launch app, probe status bar + activation policy | observed | `Bash: launch + screencapture` |
| ISC-14..21 | source+runtime | grep for API calls, then screenshot panel over wallpaper | wallpaper visible through panel | `Grep` + `screencapture` |
| ISC-22..25,29,30 | source | glyph table shape, Circle usage, tracking values | present | `Read`/`Grep` |
| ISC-27,31,32 | source | font/colour token audit in Theme + views | consistent | `Grep` |
| ISC-33..37 | unit | XCTest assertions on TimerEngine | pass | `swift test` |
| ISC-39..41 | source | pressed-state binding, spring params, env keys | present | `Grep` |

## Features

| name | description | satisfies | depends_on | parallelizable |
|------|-------------|-----------|------------|----------------|
| Package | SwiftPM manifest, targets, test target, build.sh bundler | ISC-1..8 | — | no |
| DotMatrix | 5×7 glyph table + SwiftUI dot renderer + CoreGraphics template renderer | ISC-11,22..26 | Package | yes |
| TimerEngine | deadline-based pomodoro state machine + tests | ISC-33..38 | Package | yes |
| Theme | colour tokens, type scale, tracking, spacing | ISC-27..29,31,32 | Package | yes |
| StatusItem | NSStatusItem, template image rendering, 1 Hz redraw | ISC-9..13 | DotMatrix, TimerEngine | no |
| GlassPanel | transparent NSPanel + SwiftUI glass root + anchoring + dismissal | ISC-14..21 | Theme | no |
| Dial | TE tick-ring, progress arc, drag-to-set | ISC-30,39 | Theme | yes |
| Motion | springs, materialise transition, reduce-motion/transparency | ISC-40,41 | GlassPanel | no |

## Decisions

- **2026-08-24** — Verified the Liquid Glass API surface by reading `SwiftUICore.swiftinterface` in the macOS 27.0 SDK rather than trusting recall. Confirmed `Glass` lives in **SwiftUICore, not SwiftUI**, and exposes exactly `.regular`/`.clear`/`.identity`/`.tint(_:)`/`.interactive(_:)`, with `glassEffect(_:in:)`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)`. This is the authoritative signature set for the build.
- **2026-08-24** — Chose `NSStatusItem` + custom borderless `NSPanel` over SwiftUI's `MenuBarExtra(.window)`. `MenuBarExtra`'s hosting panel supplies its own material and does not expose a documented hook to clear it; "purely transparent" is the primary aesthetic requirement, so the extra ~80 lines of AppKit buys guaranteed control over `isOpaque`/`backgroundColor`.
- **2026-08-24** — Status item drawn as a **template `NSImage`** via Core Graphics rather than an `NSHostingView`. Template images are auto-tinted by macOS for light/dark/tinted menu bars, which is the most literal reading of "blend in with Apple UI", and it costs less than hosting SwiftUI in the status bar.
- **2026-08-24** — Dot-matrix implemented as a geometric glyph table, not a bundled font. Research confirmed NDot is proprietary to Nothing; drawing the 5×7 grid is both licence-clean and *more* faithful, because it lets unlit dots render at low opacity — the actual dot-matrix-display look a font file cannot reproduce.
- **2026-08-24** — Phase-completion alert uses `NSSound` + a status-item pulse + auto-opening the panel, **not** `UNUserNotificationCenter`. User notifications require a signed, notarised bundle; an ad-hoc `swift build` product would silently fail to register. Reliability beats the conventional path here. `ponytail:` upgrade path — add UNUserNotificationCenter once the app is signed with a Developer ID.
- **2026-08-24** — Launch-at-login (`SMAppService`) deferred for the same signing reason. `ponytail:` upgrade path recorded in README.
- **2026-08-24** — Break phases deliberately have **no** accent colour. Restraint is the Nothing/TE throughline; making the accent exclusive to focus turns colour into a phase signal instead of decoration, satisfying the Principles section's "colour is a signal" claim.
- **2026-08-24** — **Delegation floor show-your-math (E3 soft floor = 2, selected = 0).** Doctrine's Forge auto-include and a parallel research agent were both candidates. The active harness directive forbids spawning agents unless the user requests them, and the user did not. What the un-selected delegation would have bought: (a) Forge/GPT-5.4 second-implementation of `TimerEngine` for cross-model correctness review — substituted by writing actual XCTest cases for the two failure modes Forge would have been asked to hunt (long-break cadence, tick-independence), which is a stronger probe than a code read; (b) a background research agent on Nothing/TE brand specs — substituted by two direct `WebSearch` calls, which returned the two facts that actually changed the design (NDot's IBM-mainframe dot-matrix lineage; TE's *exclusive* monospace rule). The delegation floor is soft and this is the math.

- **2026-08-24** — refined: switched the deadline from `Date` to `ContinuousClock.Instant` after the advisor pass. `Date` is a wall clock, so an NTP correction or DST change would jump the deadline and end a phase early or late for no visible reason. `ContinuousClock` is monotonic and, unlike `SuspendingClock`, keeps counting across system sleep — which is the behaviour a Pomodoro wants.
- **2026-08-24** — Accent colour removed from *all* text. Measured over saturated backdrops: orange labels over a warm backdrop are unreadable through clear glass. Every label is now `.primary`; the accent is confined to the status LED, swept ticks, progress arc, pips and button strokes — marks that only need to be noticed, not read. Matches apple-design § 12 ("put colour on a layer, not on the translucent foreground") and is more faithful to TE, which colours hardware and never legends.
- **2026-08-24** — Advisor findings triaged rather than adopted wholesale. Accepted: monotonic clock, `.common` run-loop mode + `beginActivity` (App Nap would freeze the visible countdown while the deadline stayed correct), `.stationary` collection behaviour, vertical clamp to `visibleFrame`. Rejected with reason: (a) the "colour-only state signal" accessibility concern — the LED always sits beside a text phase legend (FOCUS/BREAK/LONG BREAK) and a text run-state (RUN/HOLD/READY), so colour is never the sole channel; (b) "switch to `Glass.regular`" — A/B'd on identical saturated backdrops and found no legibility difference on macOS 27, so it would trade the literal requirement for nothing; (c) the advisor's `--auto-state` had loaded an unrelated agenticOS ISA, so its "state mismatch" opening was about the wrong document — this project's ISA is this file.

- **2026-08-24 (v1.1)** — "Focused time" defined as **actual elapsed, paused time excluded, floored at 60s, attributed to the local calendar day the session began.** The alternative — log only completed pomodoros — renders 24 honest minutes interrupted at the door as a blank day, and blank days for real work is what makes people abandon a tracker. The opposite error, logging the full phase length for an abandoned session, makes the heatmap flatter you, and a log that flatters you is one you stop trusting. Completed pomodoros still drive the session pips; the log measures minutes. Two metrics, two questions, deliberately separate.
- **2026-08-24 (v1.1)** — Cues are synthesised at runtime rather than bundled as audio files, for the same reason the dot-matrix is drawn rather than shipped as a font: the project's premise is that its assets are generated. Six cues, rising for beginnings and falling for stops, with the two phase-end figures ~2× the gain of the transport blips because they're the only ones you might be across the room from.
- **2026-08-24 (v1.1)** — The heatmap uses the focus accent even during a break, when the accent is otherwise suppressed. Deliberate exception to the restraint rule: that rule says colour marks *focus*, and the whole section is a record of focus. Suppressing it on breaks would make your history flicker for a reason that has nothing to do with your history.
- **2026-08-24 (v1.1)** — Intensity levels use fixed thresholds anchored to pomodoro counts (≈1/2/4/6) rather than quartiles of the user's own data. Quartiles are self-relative, so a light week would light up as brightly as a heavy one and the colour would stop meaning anything.
- **2026-08-24 (v1.1)** — Fixed a multi-display bug found during verification: the panel opened on the secondary monitor while the status item sat on the main one. `NSStatusItem.button.window.screen` returned the wrong screen, and because placement *clamps* to that screen's `visibleFrame`, a wrong answer doesn't nudge the panel — it teleports it. Now derived from the status item's own frame, which can't disagree with where the item is.
- **2026-08-24 (v1.1)** — `SND`/`QUIT` were bare `Text` in `.plain` buttons, so their hit area was the glyph bounds: a target a few points tall. Added a `HitTarget` modifier (padding + `contentShape`). Found because synthetic clicks on `SND` silently did nothing while clicks on the larger transport buttons worked.
- **2026-08-24 (v1.1)** — Advisor findings triaged. Accepted as blocking: `O_APPEND` (two instances is not hypothetical — it's what happens when a new build launches before the old one quits, and the previous `write(to:atomically:)` fallback could have replaced the entire history); trailing-newline repair; storing the local day per record (unrecoverable from the epoch once the timezone rule changes). Accepted as cheap: flush-on-quit, sandbox note. **Rejected:** the claim that the 60s floor inflates a 3-second drain to a full minute — the floor *drops* sub-60s sessions rather than rounding up; direction misread. **Already handled:** per-line tolerant parsing, non-fatal writes, and the lid-closed-for-hours case, which cannot produce an absurd entry because elapsed is `phaseLength − remaining` and is therefore clamped to the phase length by construction.

**Conjectured (v1.1)** — that `start()` then `skip()` in a unit test would exercise the abandoned-session path and log a partial duration.
**Refuted by** — the test failing with `logged.count == 0`, and a crash on `logged[0]` immediately after. With no clock advance, elapsed is genuinely zero, so *correctly* nothing was logged; the test asserted behaviour the code was right to refuse.
**Learned** — a callback-based log needs a controllable clock as much as the timer itself does. Asserting "some time was logged" without advancing time tests nothing, and a failing `#expect` does not halt the test, so the next line indexes an empty array and takes the whole suite down with a signal 5.
**Criterion now** — every log-integration test injects `TestClock`, and ISC-52 is asserted as an exact duration (`600`) rather than an inequality.

**Conjectured (v1.1)** — that pinning the envelope to zero at both ends of each note was enough to guarantee click-free cues.
**Refuted by** — `everyCueStartsAndEndsSilent` failing on the *last* sample of every cue: `progress` was computed as `frame / frameCount`, which reaches only `(n-1)/n`, leaving the final sample mid-decay at non-zero amplitude — a step discontinuity, i.e. exactly the click the envelope exists to remove.
**Learned** — an envelope is only as good as its parameterisation. "Zero at progress 1" is worthless if progress never reaches 1; off-by-one in a normalised ramp is silent in code review and audible in the product.
**Criterion now** — ISC-44 is asserted at the sample level in both a unit test and an on-device probe, denominator `frameCount - 1`.

## Verification

- ISC-1: `swift build -c release` — "Build complete! (20.12 secs)" on a cleaned package, exit 0.
- ISC-2: same run — zero `error:` / `warning:` lines from `Sources/`.
- ISC-3: `rg '\.package\(' Package.swift` → 0 matches.
- ISC-4: `find build/PomoDot.app -type f` → `Contents/MacOS/PomoDot`, `Contents/Info.plist`, `_CodeSignature/CodeResources`.
- ISC-5: `plutil -extract LSUIElement raw Info.plist` → `true`.
- ISC-6: `plutil -extract LSMinimumSystemVersion raw Info.plist` → `26.0`.
- ISC-7: `./build.sh release` regenerated the bundle from scratch, exit 0.
- ISC-8: `lipo -archs` → `arm64`.
- ISC-9/11: screenshot `docs/menubar.png` — one status item rendering `25:00` in dot-matrix.
- ISC-10: `image.isTemplate = true` in `StatusItemRenderer`; confirmed live by the item tinting white on the purple menu bar and inverting with appearance.
- ISC-12: two captures 5s apart → menu bar `24:59` then `24:54`.
- ISC-13: `app.setActivationPolicy(.accessory)`; no Dock tile observed across every launch.
- ISC-14/15: `isOpaque = false`, `backgroundColor = .clear`, `styleMask: [.borderless, .nonactivatingPanel]`.
- ISC-16/17/18: `rg 'glassEffect' Sources/` → exactly one call site, `PanelView.swift:52`, with `glass` resolving to `Glass.clear`.
- ISC-19: panel frame origin x 2362, width 292 → midX 2508, exactly the status item's midX.
- ISC-20: panel persisted 10s with no input (windows=1 at t=1,3,6,10s) and closed on an outside click.
- ISC-21: `rg 'Color\.black|Color\.white|windowBackground|\.background\(Color' Sources/PomoDotKit/` → no matches. All three `.fill(` sites are foreground marks (LED, matrix dots, pips).
- ISC-22/23/24: tests `everyDigitAndTheColonHaveGlyphs`, `everyDigitGlyphIsFiveWideAndSevenTall`, `everyDigitGlyphIsDistinct`, `layoutLightsSomeDotsAndLeavesOthersUnlit` pass.
- ISC-25: `Path(ellipseIn: rect)` / `context.fillEllipse(in:)`.
- ISC-26: `find . -name '*.ttf' -o -name '*.otf' -o -name '*.woff*'` → 0.
- ISC-27/28: `rg '\.system\(size:' Sources/` → 2 matches, both in `Theme.swift`, both `design: .monospaced`.
- ISC-29: `Theme.legendTracking = 1.6`, `numeralTracking = 0.8`, applied via the shared `Legend` view.
- ISC-30: `dialTickCount = 60`, `dialMajorTickEvery = 5`; visible in every panel screenshot.
- ISC-31/32: `Theme.accent(for:)` returns `focusAccent` only for `.focus`. Verified live — `shots/break-phase.png` shows BREAK with a grey LED, grey button strokes and grey chip; no orange anywhere.
- ISC-33/35/37: `ContinuousClock.Instant` deadline; tests `remainingIsDerivedFromDeadlineNotFromTickCount`, `remainingSurvivesAJumpLongerThanThePhase`, `pauseStoresRemainingAndResumeRecomputesAFreshDeadline`.
- ISC-34/36: `fourthCompletedFocusYieldsLongBreak`, `longBreakResetsThePipCycle`, `skippingFourFocusRunsNeverReachesLongBreak`.
- ISC-38: `swift test` → "Test run with 19 tests in 0 suites passed", exit 0.
- ISC-39: `TransportButtonStyle` scales on `configuration.isPressed`, not in the action closure.
- ISC-40: `MaterialisingPanel` animates `scaleEffect` + `blur` + `opacity` together under `Theme.springPanel`.
- ISC-41: **[DEFERRED-VERIFY]** — `accessibilityReduceMotion` / `accessibilityReduceTransparency` are read and branched on in `PanelView` and `MaterialisingPanel`, and light/dark appearance switching was probed live, but the two accessibility toggles themselves were **not** exercised. Follow-up **POMODOT-1**: enable Reduce Motion and Reduce Transparency in System Settings and capture the panel under each. Deliberately not marked `[x]` — this is a code-path claim, not a live probe.

### v1.1 — sound, focus log, heatmap

- ISC-42: `find` for `.aiff`/`.wav`/`.mp3`/`.caf` outside `.build` → 0. Every tone is synthesised.
- ISC-43/44/45: `soundprobe.swift` against the real audio device — all six cues render (`start` 4409 frames/100.0ms, `pause` 3087/70.0ms, `skip` 1234/28.0ms, `reset` 4410/100.0ms, `focusEnded` 15435/350.0ms, `breakEnded` 13671/310.0ms), every one with `first=0.00e+00 last=0.00e+00`. Transport cues peak ≈0.11, phase-end cues ≈0.21 — the intended loudness split. Tests `everyCueGeneratesSamples`, `everyCueStartsAndEndsSilent`, `cuesNeverClip`, `cuesAreDistinguishableFromEachOther`.
- ISC-46: seeded `soundMuted=true` in `com.archierichardson.pomodot`, relaunched → chip renders `MUTE` at raised opacity (`shots/muted3-z.png`). Write path confirmed by the app's own plist containing `soundMuted`, `focus=1500`, `shortBreak=300`, `longBreak=900` after a clean quit.
- ISC-47: `play(_:)` returns before `ensureEngineRunning()` when muted, so no node is started.
- ISC-48: `engine.start()` is wrapped in do/catch returning nil; probe reported `engine.start(): OK isRunning=true` on this hardware, output device 48000 Hz.
- ISC-49/50/52: **live end-to-end** — started a real session at 18:09:01 BST, skipped at 18:10:45, log contained exactly `{"seconds":106,"start":"2026-08-24T17:08:59Z"}`. 106s is elapsed, not the 25-minute phase length.
- ISC-51: `logSurvivesAReopen`.
- ISC-53: `pausedTimeIsNotCountedAsFocusedTime` — 10 min focused, 1 hr paused, logs 600.
- ISC-54: `breakPhasesNeverReachTheFocusLog`.
- ISC-55: `shortSessionsAreNotLogged` — 59s dropped, 60s kept.
- ISC-56: `dailyTotalsBucketByLocalCalendarDay` plus `theStoredLocalDayIsUsedInsteadOfRederivingIt`; each record stores its own `yyyy-MM-dd`.
- ISC-57: `corruptLineIsSkippedNotFatal` — a truncated final line costs one session, not the file.
- ISC-58: `storeIsAppendOnlyJSONLWithOneObjectPerLine`, `rollingWindowCountsWholeLocalDaysIncludingToday`.
- ISC-59: every test uses a fresh `tempDirectory()`; screenshots ran under `POMODOT_LOG_DIR`. Confirmed `~/Library/Application Support/PomoDot` stayed absent throughout ("real log untouched").
- ISC-60/61/62: `shots/v2-stats.png` after the live session — `TODAY 1m / 7 DAYS 1m / TOTAL 1m`, monospaced. `durationsFormatTersely` covers `0m`, `25m`, `4h 25m`.
- ISC-63/64/65/72: `gridIsSevenRowsByTheConfiguredNumberOfWeeks`, `eachColumnIsOneCalendarWeekInWeekdayOrder`, `todayFallsInTheLastColumn`, `gridIsContiguousAcrossWeekBoundaries`. Visually, the single logged session lit exactly the top-right cell.
- ISC-66: `intensityLevelsAreAnchoredToPomodoroCounts` — fixed thresholds, capped at level 4.
- ISC-67/68: `LESS ▪▪▪▪▪ MORE` and `LAST 26 WEEKS` visible in `shots/v2-final.png`.
- ISC-69: `rg -c 'glassEffect\(' PanelView.swift` → 1. Still exactly one glass surface after adding two sections.
- ISC-70: `rg 'Rectangle\(\)|Circle\(\)' Heatmap.swift` → two `Rectangle()`, no `Circle()`.
- ISC-71: `shots/v2-empty.png` — full grid at level 0 with the legend showing the scale; `emptyLogProducesAFullGridOfLevelZero`.
- ISC-73: panel measures 292×471 at y=36 on a 2005pt-tall screen.

**Durability matrix** (post-advisor, all in `FocusLogTests`):

| risk | probe |
|---|---|
| two instances clobbering the file | `concurrentWritersDoNotClobberEachOther` — 40 interleaved writes, none lost |
| truncated line fusing with the next record | `appendRepairsAMissingTrailingNewline` |
| history re-bucketed by a DST/timezone change | `theStoredLocalDayIsUsedInsteadOfRederivingIt` |
| logs written before the `day` field existed | `entriesWrittenBeforeTheDayFieldExistedStillAggregate` |
| double-count / lost time across transport orderings | `transportSequencesFlushEachSecondExactlyOnce` — 10 sequences |
| lid closed for hours mid-focus | `sleepingThroughAPhaseCannotLogMoreThanThePhaseLength` — capped at 25m |

**Legibility matrix** — the transparency-versus-contrast risk, probed over `backdrop` colour bands:

| appearance | backdrop | result | evidence |
|---|---|---|---|
| light | light app chrome | pass | `shots/panel4.png` |
| light | saturated yellow/red bands | pass, after moving the accent off text | `shots/panel-fixed.png` |
| dark | dark app chrome | pass | `docs/panel.png` |
| dark | saturated bright bands | pass | `shots/final-verify.png` |

The `.clear` vs `.regular` A/B (`shots/panel-bands.png` vs `shots/panel-regular.png`) showed no legibility difference on macOS 27, so `.clear` was kept as the literal reading of "purely transparent".
