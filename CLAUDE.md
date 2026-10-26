# Drift

An iOS synth app: Mutable Instruments' Plaits (voice) and Marbles (random sequencer),
compiled from the original C++ (MIT, via Worldwave's Wakes), with a native SwiftUI UI.
iPhone only, portrait, iOS 26+.

## Layout

- `DSP/third_party/` — Plaits, Marbles, Rings' reverb and stmlib sources, unmodified (from pichenettes via
  Wakes). Never edit; override instead. (Not called `vendor`: some tools skip that name.)
- `DSP/shim/` — header overrides (`plaits/user_data.h`).
- `DSP/Bridge/DriftEngine.{h,cpp}` — the C interface: parameters, rendering, routing.
  `DSP/Bridge/DriftFX.h` — the effects on the whole mix (phaser, delay, Rings' reverb,
  beat repeat), applied before volume and the limiter.
  Up to three Plaits voices (`DV_VOICES` 1 or 3). Per-voice controls (`drift_is_per_voice`)
  have a copy per voice (`drift_set_v`); Marbles, Volume, Output and the burst are shared.
  In Swift, `ParamSpec.forVoice(v)` gives a voice's copy (key `timbre@2` etc.; voice 1 keeps
  the plain key so old saves load) and `Synth.sv(p)` the active voice's. Views must use
  `synth.sv(...)` for per-voice controls.
- `App/` — SwiftUI. `Params.swift` (every control), `Synth.swift` (state, saving, motion),
  `VoiceView.swift` (Plaits page and pad), `RandomView.swift` (Marbles page),
  `FXView.swift` (FX tab, Beat Repeat strip),
  `ScopeView.swift` (Scope tab, burst strip), `Sheets.swift` (toolbar, Motion, Library),
  `Help.swift` (slider help), `Guide.swift` (the in-app Guide and What's New).
- `project.yml` — the Xcode project is generated from this with `xcodegen generate`.
  Change settings here, not in Xcode, or they are lost on the next generate.
  `Drift.xcodeproj` is git-ignored.
- `Config/Base.xcconfig` — public identity (placeholder bundle ID, no team). It includes
  `Config/Local.xcconfig` if present: the owner's team, bundle ID and icon choice.
- `Local/Assets.xcassets` — private artwork (Mutable Instruments' logos and face icon),
  used only in the owner's builds. `Config/Local.xcconfig` and `Local/` are git-ignored
  and must never be committed: the public repo uses `App/Assets.xcassets` placeholders,
  and the tabs fall back to SF Symbols when the logos aren't in the build.
- `tools/render_test.cpp` — host smoke test of the DSP, no Xcode needed.
- `LICENSE` (Drift, MIT), `NOTICE` (credits), `DSP/third_party/LICENSE-*.txt`.
  `DSP/third_party/README.md` records the upstream commits; `tools/check_upstream.sh`
  proves the files are unmodified. Credit Émilie Gillet, Worldwave/Wakes and the SP-1
  community in README, NOTICE and the Guide's Thanks page; keep all three in step.

## Building

```
xcodegen generate
xcodebuild -project Drift.xcodeproj -scheme Drift -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The user runs it on their iPhone 18 Pro Max from Xcode (free Personal Team, set in
`Config/Local.xcconfig`). They use a larger system text size: check layouts don't wrap or
truncate.

## Releases — keep the Guide up to date

Every change that alters what the app does, how it looks, or what a control means must,
in the same change:

1. Update the affected topic(s) in `App/Guide.swift` so the Guide describes the app as it
   now is. Remove anything that is no longer true.
2. Update the matching slider text in `App/Help.swift` if a control's meaning changed.
3. Add the change to the newest entry in `Guide.releases`. If the version was already
   given to the user, start a new entry instead.
4. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` for a new
   entry, and regenerate the project.

Write Guide text in plain language for a musician, not a programmer.

## Conventions

- 100 % native iOS look: no skeuomorphic knobs or hardware imagery. Sliders, not knobs.
- UI names: tabs are "Plaits", "Marbles", "FX" and "Scope"; the Marbles reseed button is "New Loop" (earlier versions called it "New Dice", then "Randomise").
- Explanations go in the ⓘ popover (`InfoButton`, text in `Help.swift`) or long-press help,
  never as footnotes on the page: every section reads the same way.
- Every new control gets help text, and an entry in `P.motionTargets` if motion should
  be able to drive it.
- Saved sounds are JSON keyed by `ParamSpec.key`: never rename a key; decode new fields
  with defaults so older saves still load.
