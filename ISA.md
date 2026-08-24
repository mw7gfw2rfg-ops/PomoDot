---
task: Build PomoDot — a transparent Liquid Glass menu bar Pomodoro timer
project: PomoDot
effort: E3
phase: verify
progress: 40/41
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

**Legibility matrix** — the transparency-versus-contrast risk, probed over `backdrop` colour bands:

| appearance | backdrop | result | evidence |
|---|---|---|---|
| light | light app chrome | pass | `shots/panel4.png` |
| light | saturated yellow/red bands | pass, after moving the accent off text | `shots/panel-fixed.png` |
| dark | dark app chrome | pass | `docs/panel.png` |
| dark | saturated bright bands | pass | `shots/final-verify.png` |

The `.clear` vs `.regular` A/B (`shots/panel-bands.png` vs `shots/panel-regular.png`) showed no legibility difference on macOS 27, so `.clear` was kept as the literal reading of "purely transparent".
