# Third-party DSP

**Upstream, unmodified.** Every file under `plaits/`, `marbles/`, `rings/` and `stmlib/` is a
byte-for-byte copy of Emilie Gillet's code. Don't edit them; override in `DSP/shim/` or
handle it in `DSP/Bridge/` instead, so an update stays a copy rather than a merge.

| Folder | Repository | Commit |
|---|---|---|
| `plaits/`, `marbles/`, `rings/` | https://github.com/pichenettes/eurorack | `08460a69a7e1f7a81c5a2abcc7189c9a6b7208d4` (2023-08-16) |
| `stmlib/` | https://github.com/pichenettes/stmlib | `d18def816c51d1da0c108236928b2bbd25c17481` (2023-09-03) |

The file set is the one Worldwave's [Wakes](https://github.com/Worldwave/Wakes) vendors:
Plaits' DSP (every engine) and resources, Marbles' random generators, ramps and resources,
and the stmlib files they need. Drift adds Rings' reverb (`rings/dsp/fx/reverb.h` and the
`fx_engine.h` it uses), for the FX tab. Nothing else from either repository is included: no
hardware drivers, UI, bootloader, hardware files, or any of the GPL-licensed AVR projects.

`DSP/Bridge/marbles_scales.inc` holds Marbles' six preset scales, copied verbatim from
`marbles/settings.cc` (via Wakes).

## Checking and updating

`tools/check_upstream.sh` downloads both repositories at the commits above and confirms
every file here is identical. To update, change the commits in the script and in this
table, copy the new files over, and run it again.

## Licence

MIT, copyright Emilie Gillet; each file carries its own notice. See `LICENSE-MI.txt`, and
`LICENSE-Wakes.txt` for the parts of `DSP/Bridge/` adapted from Wakes. The names
"Plaits" and "Marbles" label the app's pages after the modules whose code they run; with
"Mutable Instruments" they credit the original work and imply no endorsement.
