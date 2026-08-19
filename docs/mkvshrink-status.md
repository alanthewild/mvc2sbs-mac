# Project status: mkvshrink

Written for whoever picks this up next. States what is proven, what is
untested, and which conclusions are supported by measurement rather than by
reasoning.

Current build: **3.68 build 24**. `VERSION` is the repository release and must
match the newest `## X.Y` heading in `CHANGELOG.md`. `BUILD` increments on every
build handed over and is stamped into output files as
`MKVSHRINK_VERSION: "3.68 build 24"`.

## Merged into mvc2sbs-mac

Merged at repository release 3.68. The three items that were blocking are done:

1. **Version.** `mkvshrink` now carries the repository release like the other
   tools, so `VERSION` is 3.68 rather than 3.26, and the changelog entry sits
   under that heading. `BUILD` keeps counting on its own, because it answers a
   different question: which of the eight scripts written in one afternoon
   produced this file.
2. **`tests/test_version.py` covers `mkvshrink`**, both that its version matches
   the others and that it has a `BUILD` and stamps both into its output.
3. **`tests/test_mkvshrink.py` exists.** It does not cover the pipeline, which
   needs real media, but it covers the pure logic that decides what happens to
   a file: track selection, plan round-tripping, and the gates.

`mkvshrink` is also installed by `install-mac3d.sh`, shellchecked in CI and
covered by the standard-library check.

## Proven end to end on real media

One full pipeline run, Akira (1988), 12.6 GB H.264 to HEVC:

- VideoToolbox quality 62, 10-bit, 183 fps, 7.6x realtime
- length drift 0.00s, playability, Cues and chapter checks all passed
- 38 chapters intact, display dimensions preserved at 80:43 (1.85:1)
- Duration and Title carried across
- 55.7% saved against a predicted 51.9%
- **Direct Play on an Nvidia Shield through Plex**, one hour watched, no
  artefacts

Also encoded and visually checked: A Silent Voice (72.5% saved, clean),
Princess Mononoke (34.0% predicted, clean), GoodFellas (57.8% saved, under
review at time of writing).

That covers: probe, encode, mux, geometry restore, verification, and
`--keep-originals`. It is the core path and it works.

## Untested

- **`--in-situ`.** Never run. The `land_output` cross-filesystem safety was
  tested with synthetic files on two real filesystems, but not in this mode on
  real media.
- **`_replaced` folder mode on real media.** Tested synthetically only.
- **The strip-only branch on a real already-HEVC file.** The `already-hevc`
  skip fires correctly in plans, but a strip-only remux has not been run.
- **StereoMode and Full-SBS geometry.** This is the reason `mkvshrink` sits
  alongside `mvc2sbs` and none of the testing touched it. The code reads
  `stereo_mode` and `display_dimensions` and restores them with `mkvpropedit`,
  and display dimensions demonstrably survived on a 2D file, but no 3D SBS file
  has been through the tool.
- **Jellyfin.** Every muxing rule inherited here was established against
  Jellyfin on a Shield. Verification so far has been in Plex, because that is
  what the owner uses for 2D. Jellyfin remains unverified for `mkvshrink`
  output and is the reference for 3D.
- **`--apply` on a large real plan.** Works synthetically; never run at scale.
- **Rows reported as `no video track` and `interlaced`.** One of each appeared
  in a 1587-file plan. Both branches are untested and the interlaced skip may
  be excluding content unnecessarily.

## Bugs found and fixed, worth not reintroducing

Every one of these produced plausible-looking output while being wrong.

- **Subshell globals.** `build_setparams` set `SP_PRIM` and friends but was
  called inside `$( )`, so the assignments vanished and the next line referenced
  them under `set -u`. Every encode died on the first file, with the error
  swallowed by a `>/dev/null 2>&1` on the probe call.
- **ffmpeg eating stdin.** The `psnr` and `ssim` calls in the probe loop lacked
  `-nostdin`, so each consumed the remaining probe windows from the here-string
  feeding the loop. The loop ate its own work queue. How many windows survived
  depended on buffering, so the same file returned 15.8% and 49.3% on
  consecutive runs. Fixed with `-nostdin` everywhere **and** by reading the
  queue from a dedicated file descriptor.
- **PSNR paired by timestamp.** A stream copy and a re-encode of the same
  frames disagree in the millisecond after rounding, and the `psnr` filter
  matches on PTS. It compared frame N with frame N-1 and reported 27.8 dB on
  content actually at 43.2. Now paired by index with `setpts=N`.
- **Video byte estimate unbounded in both directions.** When per-track sizes
  were unavailable it arrived as zero, and `pred = 0 * ratio + other +
  overhead` made overhead absorb the whole file, so good candidates reported
  "saves 0.0%". Akira was rejected at ratio 0.48. When the bitrate fallback
  overshot, predictions like -212% appeared. Now clamped to what the container
  can hold, and falls back to the file minus identified tracks when zero.
- **Stale probe globals.** Skipped files inherited the PSNR of the last file
  that was probed, so a plan showed fifteen consecutive rows sharing one value.
  Now cleared per file.
- **`float("N/A")` in the progress reader.** ffmpeg's first `-progress` block
  reports `N/A` before the encoder produces output. The unguarded conversion
  killed the reader on line one, ffmpeg wrote the rest to a dead pipe, and the
  encode completed perfectly with no progress output and no visible error.
- **10-bit luma statistics.** `signalstats` reports in source bit depth, so
  10-bit files were measured on a 0-1023 scale against thresholds written for
  0-255 and looked four times wider than they were. Now normalised.
- **Cross-filesystem replace.** With `--temp` on a scratch disk, the final `mv`
  is a copy, not a rename. In folder mode the original had already been moved
  aside, so an interrupted copy could leave a partial file and no original.
  Now the output is copied to the destination filesystem and size-checked
  before anything is renamed.
- **Multiple default track flags.** Selection only patched the case where the
  dropped track carried the default. Sources with the default flag on every
  subtitle track produced outputs with three defaults. Now exactly one per type
  is asserted.
- **`--plan /path/to/folder`.** Read the folder as the plan filename, leaving
  no inputs, and printed usage to stdout where the user's redirect hid it. Now
  rejected with the corrected command line, and error usage goes to stderr.

## Open questions

**Where the quality boundary sits.** PSNR failed as a predictor in three of
four cases. `--luma` correlates with the one known failure but does not
separate the films cleanly: 5% clean, 25% clean, 37% under test, 44% damaged.
Two hypotheses have now been tried and neither produced a usable automatic
gate. Recommended policy is to sweep animation freely, treat dark live action
as a manual decision, and use `--keep-originals` where unsure.

Resist fitting a threshold to Blade Runner 2049. It is currently a single
failure and any rule derived from it alone is curve-fitting.

**Whether the two-signature theory holds.** Low ratio with low PSNR (gradient
starvation, dangerous) against high ratio with low PSNR (grain, harmless). Four
films is not enough. GoodFellas contains one probe window at ratio 0.086 and
37.5 dB, the Blade Runner signature, inside a film whose other windows look
ordinary. Watching 1:05:25 of that output is a natural experiment worth
completing.

**Track order correlation.** `mkvmerge` and `ffprobe` are correlated by
position within type, and disagree on a significant share of real files,
including Akira and Princess Mononoke. When they disagree, per-track sizes are
unavailable, so the track-drop saving cannot be counted and the encode
prediction falls back to container arithmetic. Correlating by codec and
language instead of position would fix it properly.

**Cues detection.** Verification scans the first and last 16 MB for the raw
Cues element ID, excluding SeekHead references. On a 5.8 GB file that is 0.5%
of the bytes, so it could produce a false positive from video data containing
the pattern, and would miss Cues written between the two windows. A proper walk
of the top-level EBML elements would be certain rather than probable. Nothing
has failed because of this.

**Dry-run output is misleading.** `-n` prints the ffmpeg command only, so it
reads as though that is the whole job when it is step 4 of 7. The mux, geometry
restore and verification stay silent. Either print all steps as templates, or
print a summary instead of the raw command.

## Measured settings

VideoToolbox quality 62, 10-bit, is confirmed as the right default. It sits on
the knee of the quality curve; above 65 is waste. x265 CRF 20 is marginally
smaller and marginally worse for twenty-five times the encode time.

Encoding is media-engine bound, not CPU or network bound. Roughly 7.6x realtime
at 1080p on an M1 Pro, about 184 fps. There is one media engine, so parallel
encodes split it and gain nothing; serial processing is deliberate and there is
no `--jobs` flag. A gigabit full-duplex link to a NAS is not a constraint at
these rates: reads sat near 200 Mbit/s of a 940 Mbit/s path.

## Library findings

From a 60-file anime plan and a 1587-file movies plan:

- A meaningful share of both libraries is already HEVC and correctly skipped.
- Anime compresses far better than live action, but production era and surface
  texture predict the ratio rather than "animation" as a category. 2023 digital
  production reached 82.9%; deliberately textured modern Ghibli reached 25.5%.
- Low-bitrate WEB-DL sources inflate rather than shrink, with ratios above 1.0.
  The `--min-size` gate catches most of them cheaply.
- Films carrying many junk audio and subtitle tracks are worth remuxing even
  when the video is not worth re-encoding. SRT tracks are text and tiny, so the
  byte-based strip gate will never fire on a file with thirty of them. If track
  clutter matters, that needs a count-based trigger rather than a byte-based
  one.
