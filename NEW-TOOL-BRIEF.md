# Brief: mkvshrink

A second tool for the same repository. Re-encodes existing H.264 MKV files to
HEVC to reclaim disk, with track selection. Not related to MVC or 3D decoding,
but it shares the same output path and must inherit the same hard-won rules.

Written at the end of the session that produced mvc2sbs 3.24, so that a fresh
conversation starts with the conclusions rather than rediscovering them.

## Decisions still open

1. **Originals.** Never delete, move to a `_replaced` folder after checks pass,
   or replace in place. Affects how much free disk a sweep needs.
2. **Default encoder.** VideoToolbox (about 25x faster) or x265 (about 8%
   smaller), or choose per file by size.
3. **Input handling.** Files and folders on the command line, recursion into
   subfolders, skipping files that are already HEVC, skipping files where the
   saving would be small.

## Rules this tool must inherit

Every one of these was a real fault that cost hours to find. They are not
preferences.

**Mux with mkvmerge, never FFmpeg.** Both write valid Matroska with identical
streams, and every field `mkvdiff` checks agrees between them, but Jellyfin's
Android TV client on an Nvidia Shield refuses to direct play FFmpeg's output and
plays MKVToolNix's. Established by remuxing one file with
`mkvmerge -o new.mkv old.mkv`, changing nothing else, and watching it start.
FFmpeg encodes to a staging file; mkvmerge produces the file you keep.

**mkvmerge exits 1 for warnings and 2 for failure.** Treating any non-zero exit
as failure means a perfectly good file gets thrown away and FFmpeg's mux kept
instead, which is exactly the mux that will not direct play. Capture its output
and print it: `mkvmerge -q` says nothing on success, and a bare "mkvmerge
failed" tells you nothing at all.

**Delete large intermediates the moment they stop being needed, not at the end
of the run.** A remux writes a second complete copy of the film before the first
can be deleted. Holding the elementary stream through that meant a 45 GB rip
needed about 100 GB free. Check free space before the remux, while the encode is
still safe in the staging file and the answer is still actionable.

**FFmpeg rebases every input file to start at zero.** Any input whose first
timestamp is not zero, a subtitle .sup being the obvious one, has its own start
time subtracted. A film whose first subtitle is 44 seconds in gets a subtitle
track that runs 44 seconds early for its whole length, in a file that passes
every structural check. Pass `-itsoffset` equal to the input's own `start_time`.

**Never let FFmpeg write chapters.** It emits a `ChapterTimeEnd` on every
chapter, which Matroska only defines for ordered editions. Players that read it
as one build a broken virtual timeline: VLC showed no video window for the first
47 seconds of a feature, Kodi needed a manual skip, Jellyfin refused the file
outright. Pass `-map_chapters -1` and carry chapters across with `mkvextract`,
stripping `ChapterTimeEnd`, then hand them to mkvmerge with `--chapters`.

**Start the filter chain with `setparams`.**

```
setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv
```

Asking FFmpeg 8 for bt709 output on untagged frames is a conversion request, not
a labelling one, and converting transfer characteristics goes through linear
light, so swscale routes every frame through 16-bit RGB. It announces itself as
`No accelerated colorspace conversion found from yuv420p to bgr48le` and it is a
full colour round trip on every frame. Only bites at 10-bit, because at 8-bit no
scaler is inserted. A `format=` filter does **not** fix it.

**Preserve StereoMode and display dimensions.** Some of the files this will be
pointed at are 3D SBS conversions. A Full-SBS file must declare display
dimensions of 3840x2160, not the per-eye 1920x1080 a plain reading of the spec
suggests. Both express 16:9, but Jellyfin refuses a file whose declared display
is smaller than its coded frame. Read `stereo_mode` and `display_dimensions` from
the source with `mkvmerge -J` and restore them with `mkvpropedit`.

**Check the output, not just the exit status.** After every encode:

- length against the source, warn above one second of drift
- decode the first three seconds and count frames, because a file can be the
  right length and still not start
- Cues present, distinguishing the element from a SeekHead reference to it
- chapters not ending past the end of the file

**Stamp provenance into the file.** Tags `MVC2SBS_VERSION` and
`MVC2SBS_SETTINGS` for mvc2sbs; use equivalent names here. Not `ENCODER`, which
ffprobe overwrites with the muxer's writing app. Working out which build and
which settings produced a file, from a folder full of them, is otherwise
guesswork, and guessing wrong sends you chasing faults fixed two versions ago.

## Settings, measured

On one minute of 3840x1080, each compared against a common near-lossless
reference. M1 Pro.

| Encode | Size | PSNR | SSIM | Time |
| --- | --- | --- | --- | --- |
| x265 CRF 20 `slow` 10-bit | 178 MB | 46.16 dB | 0.9811 | 6 m 47 s |
| VideoToolbox quality 62 10-bit | 192 MB | 46.45 dB | 0.9823 | 0 m 15 s |
| VideoToolbox quality 65 10-bit | 235 MB | 46.88 dB | 0.9840 | 0 m 16 s |

- **10-bit always.** Dither retention goes from ~52% to ~90% on a dark ramp,
  which is what stops banding, at no cost in size or speed.
- **CRF 20, not 16.** CRF 18 and 20 sat 46.5 dB apart on the most expensive
  minute of a film, below what a display shows, and 18 cost 2.8 GB more.
- **No `--dark` at 10-bit.** Worth 5 to 8 points of dither retention at 8-bit,
  nothing at 10-bit, and 20 to 40% more bits.
- **VideoToolbox quality 62** matches x265 CRF 20. The scale is not a CRF and
  higher is better. Above 65 is waste: quality 80 was four times the size for no
  measurable gain.
- These were calibrated at 3840x1080. **Recalibrate for 1080p 2D** before
  sweeping a library: encode one clip at a few settings and compare against a
  near-lossless reference with `mkvdiff --quality`.

## Method, which mattered more than any single fix

- **Cut a test clip once with `mkvmerge --split parts:`** and encode that, rather
  than using a seek option on the full source. Every encode then starts on the
  identical frame. Seeking snaps to a keyframe, so two runs can begin on
  different frames and still produce a confident-looking PSNR.
- **`mkvdiff --quality A B` measures how far apart two files are, not which is
  better.** To rank encoders, compare each against a common near-lossless
  reference.
- **Pick the test clip deliberately.** A film's opening is usually its cheapest
  minute. `mkvdiff --peak` finds the most expensive one, though note that "most
  expensive" means bitrate, which can be grain in the dark rather than motion.
- **Two faults at once will make a correct single-variable test look like an
  exoneration.** The chapter fault was tested in isolation and cleared, because
  the display-dimension fault was still present underneath it.
- **Identical on every field you happen to check is not identical.** The original
  conclusion that HEVC would not play on a Shield was drawn from four files that
  agreed on every field `mkvdiff` measured at the time. The fault was in a
  property it did not yet measure.
