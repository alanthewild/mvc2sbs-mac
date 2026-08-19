# MVC2SBS

Convert 3D Blu-ray MVC rips into side-by-side MKV files, natively on macOS.

A replacement for the [BD3D2MK3D](https://www.videohelp.com/software/BD3D2MK3D)
step of the usual 3D ripping workflow, so you no longer need a Windows VM. Ships
as a command line tool and a small Mac app.

![MIT licence](https://img.shields.io/badge/licence-MIT-blue)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey)
![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)

---

## Why this exists

The hard part of converting a 3D Blu-ray is decoding the MVC dependent view. On
Windows that is done with AviSynth plus `H264MVCSource` or FRIM, neither of
which exists on macOS, and mainline FFmpeg has no MVC decoder at all.

[edge264](https://github.com/tvlabs/edge264) solves it: a small BSD-licensed
H.264 decoder with Stereo High profile support and a native ARM NEON path. The
[MVC fork](https://github.com/cbusillo/edge264-mvc) emits both views side by
side as a Y4M stream on stdout, which pipes straight into x264.

Everything else BD3D2MK3D wraps around that step collapses into one shell
pipeline. The result is faster than the same work in a VM, mostly because
extraction is no longer crawling through a shared folder, and because x264 runs
natively on all cores.

Measured, on Gravity (1:31, 3840x1080 output):

| Encode | Machine | Rate | Full film |
| --- | --- | --- | --- |
| x264 CRF 16, `slow` | M1 | 11.7 fps | 3 h 11 m, measured end to end |
| x265 CRF 20 10-bit, `slow` | M1 Pro | 13 fps on the opening | not known |
| x265 CRF 18 10-bit, `slow` | M1 Pro | 2.5 fps at 26:30 | not known |
| VideoToolbox HEVC | M1 Pro | 99 fps on the opening | not known |

**Do not extrapolate an encode time from a one minute clip.** The same settings
on the same film ran at 13 fps on the opening and 2.5 fps twenty-six minutes in.
Gravity opens on near-black at under 2 Mbps and peaks above 67 Mbps later, and
x265 slows down in proportion. A figure taken from the opening will be
optimistic by a large multiple.

If you need a real estimate, sample three or four points across the film with
`--start` and average them, or just start the encode and read the rate.
VideoToolbox is the option to reach for when time matters: it runs on the media
engine rather than the cores, and the gap is roughly an order of magnitude.

Roughly twice the speed of the same work in a Parallels VM, mostly because
extraction is no longer crawling through a shared folder and the encoder gets
all the cores.

## Recommended settings

```sh
mvc2sbs --vt --10bit --vt-quality 62 INPUT.mkv
```

Confirmed to direct play on an Nvidia Shield. Wall clock on an M1 Pro, with the
source on a gigabit NAS:

| Film | Extract | Encode | Remux | Total |
| --- | --- | --- | --- | --- |
| 1 h 30 | ~4 min | ~22 min | ~3 min | around 30 min |
| 3 h 00 | ~4 min | ~44 min | ~6 min | around 55 min |

Extraction does not scale with runtime. A MakeMKV MVC rip is bounded by the disc
rather than the film, so it lands between 30 and 45 GB whether the feature is
ninety minutes or three hours. A longer film is encoded at a lower bitrate, not
from a bigger source.

The encode itself runs at 97 fps regardless of how demanding the scene is, which
is the useful property of a hardware encoder: x265 varied between 3 and 13 fps on
the same film depending on content. Extraction is network bound, so a local
source is quicker. If you would rather trade time for a slightly smaller file, or
you do not trust a hardware encoder:

```sh
mvc2sbs --x265 --10bit -q 20 -p slow INPUT.mkv
```

Same measured quality, about 8% smaller, and most of a day to encode. Either is
roughly a third the size of the x264 CRF 16 this tool originally recommended.

Every part of that is measured rather than reasoned:

- **x265 over x264.** Roughly a quarter of the bitrate. An earlier version of
  this file said HEVC would not play on a Shield at all; that was two container
  faults producing the same symptom, not the codec.
- **10-bit.** Takes dither retention from 52% to 90% on a dark ramp, which is
  what stops banding, and costs nothing in size.
- **CRF 20 over 18.** 46.5 dB PSNR between them on the most expensive minute in
  the film. Below what a display can show, and CRF 18 costs 2.8 GB a film.
- **VideoToolbox quality 62.** Matched x265 CRF 20 on PSNR and SSIM against a
  common reference, and indistinguishable on a plasma, at 27 times the speed.
- **No `--dark`.** Worth 5 to 8 points of dither retention at 8-bit, nothing at
  10-bit, and about 1 GB a film.

Check it on your own player with a one minute clip before committing hours:
`mvc2sbs --limit 60 -p ultrafast --x265 --10bit INPUT.mkv`

## Requirements

- Apple Silicon Mac, macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh)
- FFmpeg and MKVToolNix. Both are required: mvc2sbs refuses to start without
  MKVToolNix, because a container FFmpeg wrote may not direct play at all.
  ```sh
  brew install ffmpeg mkvtoolnix
  ```
- [MakeMKV](https://www.makemkv.com) to produce the source files

Intel Macs will build and run but have not been tested.

## Install

```sh
git clone https://github.com/alanthewild/mvc2sbs-mac.git
cd mvc2sbs-mac
./install-mac3d.sh            # CLI tools into ~/.local/bin
cd app && ./build-app.sh --install   # the Mac app into /Applications
```

The app bundles `mvc2sbs`, `pgs3d.py`, `mkvdiff`, `subs3d` and the MVC decoder
inside itself, so it
works even if you skip `install-mac3d.sh`. FFmpeg is always external.

Those bundled tools are a snapshot taken at build time, so editing `mvc2sbs` in
the repository does not change an installed app until you rebuild. The app
version is stamped from the script it bundles and checked at runtime, so a stale
bundle shows a warning rather than failing later with an unknown option.

## Ripping: get this right or nothing else matters

When ripping a 3D disc in MakeMKV you must tick the video track labelled
**Mpeg4 MVC**. It is off by default, and without it there is no second view to
extract.

Do not trust the codec ID afterwards. MakeMKV usually writes both views into one
track that mkvmerge labels `V_MPEG4/ISO/AVC`, with the subset SPS and the
dependent view slices carried in band. A track that says AVC can still be a
perfectly good MVC stream. `mvc2sbs --info` scans the actual bitstream for NAL
type 15 and type 20, which is the only check that means anything.

## Usage

```sh
mvc2sbs Movie_t00.mkv                       # Full-SBS, CRF 16, preset slow
mvc2sbs -q 18 -p slower --dark Movie_t00.mkv
mvc2sbs --layout hsbs -o ~/Movies/out.mkv Movie_t00.mkv
```

### Check before committing hours

```sh
mvc2sbs --info Movie_t00.mkv     # tracks, MVC NAL scan, decoder check
mvc2sbs --preview Movie_t00.mkv  # one frame to PNG, measures left/right difference
mvc2sbs --limit 60 Movie_t00.mkv # encode the first minute only
```

`--info`, `--preview` and `--limit` extract only the seconds they need rather
than the whole stream.

### Options

| Option | Meaning |
| --- | --- |
| `-q N` | CRF for x264 and x265. 20 is the measured recommendation. |
| `-p P` | x264/x265 preset. `slow` by default. |
| `--layout L` | `fsbs` (3840x1080, default), `hsbs`, `ftab`, `htab`. |
| `--dark` | Dark gradient tuning. See [Banding](#banding). |
| `--10bit` | 10-bit output. Pair with `--x265` or `--vt`, never with x264. |
| `--x265` | HEVC instead of AVC. |
| `--vt` | Apple VideoToolbox HEVC. Fast, not CRF quality. |
| `--sub-depth N` | Subtitle disparity in pixels. Positive is towards the viewer. |
| `--sub-brightness G` | Gamma on subtitle luminance. Below 1 brightens edges. |
| `--sub-colour C` | `source`, `white`, `yellow`, `amber`, `cyan`, `green`. |
| `--sub-opacity F` | Subtitle alpha multiplier. |
| `--maxrate M` | Cap the peak bitrate at M Mbps. CRF has no ceiling on its own. |
| `--flat-subs` | Keep the original 2D subtitles. |
| `--no-chapters` | Drop chapters. See [Black screen and no audio](#black-screen-and-no-audio). |
| `--audio-tracks L` | Comma list of audio tracks to keep. `--sub-tracks` likewise. |
| `--temp DIR` | Scratch directory. Never put this on a network share. |
| `--keep-temp` | Keep the extracted stream so re-encodes skip extraction. |
| `--extract-only` | Extract and stop. Useful with a NAS source. |
| `--single-thread` | Slower, more tolerant decoding for problem discs. |
| `--extra "..."` | Raw FFmpeg arguments. |
| `-n` | Print the commands without running them. |

`mvc2sbs --help` lists everything.

## What is in this repository

Everything here is source. Nothing is compiled, and there are no binaries to
take on trust.

| File | What it is |
| --- | --- |
| `mvc2sbs` | The converter. A bash script, despite having no extension. |
| `pgs3d.py` | The PGS subtitle transform. Python, no dependencies. |
| `mkvdiff` | The diagnostic comparison tool. Also a bash script. |
| `subs3d` | Builds 3D subtitles, PGS and ASS, from an SRT or an ASS. |
| `mkvshrink` | Re-encodes H.264 libraries to HEVC to reclaim disk. |
| `docs/` | mkvshrink's own README and its status report. |
| `install-mac3d.sh` | Installs the Homebrew dependencies and builds the decoder. |
| `app/Sources/*.swift` | The Mac app, five files. |
| `app/build-app.sh` | Builds the app with `swiftc`. No Xcode project. |
| `app/make-icon.py` | Generates the icon. Needs Pillow, only if you change it. |
| `app/MVC2SBS.icns` | The generated icon, committed so builds do not need Pillow. |
| `tests/` | The test suite. Eleven files, each written after a real fault. |

The scripts have no file extension because they are meant to be run as commands.
`file mvc2sbs` will confirm they are plain text.

**The one binary in a built app is not from this repository.** `edge264_test`
is compiled from [edge264-mvc](https://github.com/cbusillo/edge264-mvc) by
`build-app.sh`, which clones and builds it if it is not already present, then
copies the result into `MVC2SBS.app/Contents/Resources/`. Its source is
upstream, its licence is BSD, and its copyright notice is reproduced in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

### mkvshrink

A second pipeline in the same repository, and not a 3D tool. It re-encodes
existing H.264 files to HEVC to reclaim disk, dropping the audio and subtitle
tracks you will never play.

```sh
mkvshrink --keep-originals film.mkv            # one file, original untouched
mkvshrink --plan plan.tsv /Volumes/Media       # review before committing
mkvshrink --apply plan.tsv
```

It is here rather than in its own repository because it inherits every rule this
project paid for: mux with MKVToolNix and never FFmpeg, never let FFmpeg write
chapters, preserve StereoMode and display dimensions, check the output before
touching the original, and stamp provenance into the file. Some of the files it
will be pointed at are the side-by-side conversions `mvc2sbs` produced.

Two documents rather than a section here, because it has enough of its own:

- **[docs/mkvshrink.md](docs/mkvshrink.md)** is how to use it, what the gates
  are, why PSNR is not a quality gate, and what `--luma` is for.
- **[docs/mkvshrink-status.md](docs/mkvshrink-status.md)** is what is proven,
  what is untested, and which conclusions rest on measurement. Read this one
  first if you are about to point it at a library. It says plainly that
  `--in-situ` has never been run and that no 3D file has been through the tool.

It shares the repository version, and carries its own `BUILD` number on top,
stamped into every output file. A release version alone cannot tell you which of
eight scripts written in one afternoon produced a given file.

## How it works

```
ffmpeg          copy the MVC track out as an Annex B .264 file
edge264_test    decode base and dependent views, emit side-by-side Y4M
pgs3d.py        rebuild the PGS subtitles for the wider frame
ffmpeg          encode to a staging file, with the original audio and subtitles
mkvmerge        write the file you keep, carrying the chapters across
mkvpropedit     tag it with StereoMode and 3840x2160 display dimensions
```

Only the video is re-encoded. Audio is stream-copied. Subtitle bitmaps are
repositioned but never re-encoded.

The intermediate `.264` exists because `edge264_test` memory-maps its input, so
it needs a real file rather than a pipe. It is roughly the size of the source
video, 25 to 45 GB for a feature, and it is deleted afterwards. If the output
folder is on a network volume the scratch falls back to local storage
automatically.

## Nothing here is lossless

Worth stating plainly, because the "Archive" preset name invites the opposite
assumption. Every setting re-encodes the video. CRF 16 is close enough that the
difference is very hard to see, but it is not a copy of the source. Only CRF 0
is mathematically lossless, and for a 3840x1080 feature that runs to hundreds of
gigabytes.

What is preserved exactly: audio is stream-copied, subtitle bitmaps are
repositioned without being re-encoded, and on the full layouts no pixel is
resampled. The geometry is 1:1. The compression is not.

## 3D subtitles

PGS subtitles are authored against a 1920 wide frame. Copy one unchanged onto a
3840 wide side-by-side frame and it renders into the left eye only, which is why
2D subtitle tracks look broken in 3D players.

The fix needs no pixel work, but it does need the bitmap rebuilt, and the
reason is worth reading before you assume otherwise.

A PGS display set positions bitmaps using composition objects, and the format
allows several, so the obvious fix is to place the same bitmap twice. That is
what this tool did first. FFmpeg draws every composition object, so VLC showed
both copies and the files looked correct. ExoPlayer, which is what Jellyfin's
Android TV client decodes PGS with, reads the position of composition object 0
and ignores every one after it. The right eye was empty on the exact device
these files are made for, and what looked like a subtitle there was crosstalk
from the left.

So `pgs3d.py` splices the two copies into one bitmap, emitted as one object with
one composition object and one window, which any decoder can draw. The splice
works on RLE run boundaries rather than pixels: rows are cut apart, transparent
runs inserted between the copies, and the original bytes replayed verbatim.
Nothing is decoded or re-encoded, palettes pass through untouched, and a feature
length track converts in about a second and a half.

Check any file without watching it:

```sh
mkvdiff --subs FILE
```

This happens automatically on the `fsbs` and `ftab` layouts. The half layouts
would need the bitmaps rescaled, which is not implemented, so they keep the
original 2D tracks.

`pgs3d.py` also works standalone:

```sh
pgs3d.py in.sup out.sup --width 3840 --depth 12
pgs3d.py in.sup out.sup --width 1920 --height 2160 --stack
pgs3d.py in.sup out.sup --width 3840 --brightness 0.7 --colour yellow
```

### Pale subtitles

On a 1080p display the player squeezes the whole 3840 wide frame, subtitle plane
included, down to 1920 before the TV stretches each half back out. Measured on
simulated subtitle text, that 2:1 squeeze and stretch drops the mean luminance
of lit pixels from 229 to 187, an 18% loss, with the peak unchanged. The result
reads as pale and soft.

`--sub-brightness` applies a gamma to the palette luminance to counteract it.
Below 1 lifts the anti-aliased midtones and leaves black and peak white where
they were:

| Gamma | Y ramp |
| --- | --- |
| 1.00 | 16, 60, 110, 160, 200, 235 |
| 0.85 | 16, 72, 123, 169, 205, 235 |
| 0.70 | 16, 87, 137, 179, 210, 235 |

An earlier version of this file claimed each eye only ever gets 960 pixels of
horizontal detail on a 1080p 3D TV. That is wrong, and it came from misusing the
word "frame-compatible".

**Frame-compatible** means both views squeezed into one frame of an existing
standard size, so they travel through equipment that knows nothing about 3D.
Half-SBS is frame-compatible: 1920x1080 total, 960x1080 per eye. Half-TAB is
too, at 1920x540 per eye. Broadcasters used these because they fit 1080p
infrastructure unchanged, and they are the reason "3D looks soft" is a common
memory.

Full SBS is not frame-compatible. It is 3840x1080, a full 1920x1080 per eye,
which is exactly what a 3D Blu-ray carries and exactly what a Blu-ray player
sends a TV over HDMI 1.4 frame packing. Nothing is thrown away, and an
active-shutter 1080p 3D TV shows each eye a full 1920x1080 picture.

That full resolution is the whole point of this layout, and it is also why
support is patchy: 3840x1080 is not a resolution hardware decoders were designed
around, so some players direct play it and others transcode. Measured so far:
Kodi and Jellyfin direct play it, Plex does not.

### Adding subtitles to a film that has none

Everything above is about subtitles a disc already carries. `subs3d` is for the
other case: you have a Full-SBS film with no subtitles and an SRT or an ASS.

```sh
subs3d dialogue.srt --depth 20 --mux "Film.3D-fsbs.mkv"
```

A player draws an ordinary subtitle once, across the whole frame, so on a
side-by-side file each eye gets half the sentence. This writes every line twice,
centred in each eye, and `--mux` puts the result in the film with mkvmerge.
Nothing is re-encoded, so it takes minutes.

It writes **both formats by default**, because no single one plays everywhere
and the player can pick:

| Format | Where it works | Where it does not |
| --- | --- | --- |
| PGS | Everywhere a disc's own subtitles work, including direct play on a Shield. The typeface is baked into the bitmaps, so no font is needed on the player. | Some browser and smart TV clients, which transcode anyway. |
| ASS | VLC, mpv, Kodi, Infuse. Small, and the player can restyle it. | ExoPlayer's support is partial, so Jellyfin may ignore the positioning or burn it in. |

`--format pgs` or `--format ass` writes just one. `--depth N` sets disparity in
pixels: positive brings the subtitles towards you, which stops them colliding
with anything popping out of the screen, and 20 to 40 is a sensible range.

Two things to know. The PGS renderer needs FFmpeg built with libass, and `--mux`
needs ffprobe and mkvmerge; without `--mux` it needs nothing but python3. And
the font named in an ASS has to exist on whatever plays the film, not on the Mac
that made it, which is why the default is Arial.

## Player compatibility

Frame-compatible 3D is a niche, and hardware decoders were never tested against
3840x1080. What follows was measured on one setup: an NVIDIA Shield TV (2017,
Tegra X1) running the Jellyfin Android TV client against a Jellyfin server,
output to a Panasonic VT60 plasma.

| Output | Direct Play |
| --- | --- |
| H.264 High, 8-bit, 3840x1080 | plays |
| H.264 High 10, 3840x1080, x264 | refused, "profile is not supported", transcoded |
| HEVC Main, 8-bit, 3840x1080, x265 | plays |
| HEVC Main 10, 3840x1080, x265 | plays |
| HEVC Main, 3840x1080, VideoToolbox | plays |
| HEVC Main 10, 3840x1080, VideoToolbox | plays, and is the default |

All of it plays. Earlier versions of this file said the opposite, and that was
wrong.

The original test found no HEVC variant would play. Every file in it was muxed
by FFmpeg and carried FFmpeg's chapters, both of which are now known to make
this hardware refuse a file outright, and both of which produce the same "black
screen, no audio" symptom. The codec was never the variable. The four files were
identical in every field `mkvdiff` checked at the time, which is what made the
conclusion feel safe, and the fault was in a property it did not yet measure.

Two things worth taking from that. Identical on every field you happen to check
is not identical. And when several files share a pipeline, a fault in the
pipeline looks exactly like a property of whatever you were varying.

Codec is therefore a free choice on this hardware, and HEVC is worth taking:
roughly a quarter of the bitrate of H.264 on the same content in a one minute
sample, and 10-bit is a better answer to banding than `--dark` is.

## Banding

You cannot get less banding than the source has. The goal is to avoid adding
any. A Blu-ray master hides banding with fine dither, and banding appears when
an encoder quantises that dither away.

Measured on a synthetic dithered dark ramp at CRF 16, preset slow, tracking how
much of the source dither survives.

**x264**

| Encode | Dither kept | Size |
| --- | --- | --- |
| 8-bit, default | 58% | 55 KB |
| 8-bit, `--dark` | 63% | 81 KB |
| 10-bit, default | 83% | 10 KB |
| 10-bit, `--dark` | 91% | 12 KB |

**x265**

| Encode | Dither kept | Size |
| --- | --- | --- |
| 8-bit, default | 52% | 12.3 KB |
| 8-bit, `aq-mode=3` | 43% | 20.8 KB |
| 8-bit, `strong-intra-smoothing=0` | 47% | 12.1 KB |
| 8-bit, `sao=0` | 56% | 10.8 KB |
| 10-bit, default | 90% | 6.7 KB |
| 10-bit, `--dark` | 89% | 9.3 KB |

Three things follow, and two of them correct earlier versions of this file.

**Bit depth is the lever, not the tuning.** 10-bit roughly doubles how much
dither survives on both encoders. Every parameter tweak is worth a few points
next to that.

**`--dark` does almost nothing at 10-bit** and costs 20 to 40% more bits. At
10-bit the encoder already has the precision, and the tuning has little left to
recover. Use it at 8-bit, skip it at 10-bit.

Confirmed on real footage as well as the ramp. One minute of Gravity's opening,
x265 10-bit CRF 20, encoded with and without `--dark` and compared on a plasma:
no visible difference, 62 MiB against 54 MiB. On a feature that is about a
gigabyte for nothing.

**x265's tuning was wrong.** It used to set `strong-intra-smoothing=0`, which
this file justified as "a well known cause of gradient banding". Measured, that
setting made dither retention worse, not better. It now sets `sao=0`, which
retained more dither than the default *and* produced a smaller file. SAO is a
smoothing post-filter, and dither is what it smooths.

`aq-mode=3` is kept for both encoders, but note that the dark-ramp test cannot
evaluate it. The frame is dark everywhere, so there are no bright regions for it
to move bits away from, which is the whole point of the setting. It measures
badly here and that result should not be trusted for real footage.

### The cost of 10-bit at 3840x1080

Before spending time here, check [Player compatibility](#player-compatibility).
Every HEVC variant direct plays on the setup this was measured on, so the real
question is speed.

Measured on an M1 Pro, encoding the same content:

| Encoder | Rate | A 1h53m film |
| --- | --- | --- |
| x264, preset slow, 8-bit | 18 fps | 2.5 h |
| x265, preset slow, 10-bit | 3 to 5 fps | 9 to 15 h |
| VideoToolbox HEVC, hardware | ~100 fps, quality-targeted | ~27 min |

x265 at this resolution is not a practical default. `--vt` encodes on the Apple
Silicon media engine at around 100 fps and does support 10-bit, so it sidesteps
the speed problem entirely. It is quality-targeted rather than CRF, so it needs
more bits for the same result.

`--10bit` is the bigger win for banding, and on the one setup this has been
tested against it plays.

The codec it is paired with is what matters. `--10bit` alone produces H.264 High
10, which no NVIDIA hardware decoder has ever supported and which most TVs and
set-top boxes reject: a 2017 Shield refuses it, Jellyfin reports "the video
codec's profile is not supported", and the transcode it falls back to also
mangles the aspect ratio. Paired with `--x265` or `--vt` it produces HEVC Main
10, which direct plays. See [Player compatibility](#player-compatibility).

So: 10-bit yes, but never with x264.

An earlier version of this file said no HEVC variant played at all. That was
wrong, and the story of how is worth reading, because the mistake was in the
method rather than the measurement. See the same section.

Still worth building a 60 second clip and playing it on your own hardware before
committing hours. `--dark` is not the fallback it once was: measured on a
dithered dark ramp it is worth 5 to 8 points of dither retention at 8-bit and
essentially nothing at 10-bit, where it costs 20 to 40% more bits for no
measurable gain.

## StereoMode and display dimensions

Setting `StereoMode` without setting the display size leaves it at the packed
3840x1080, so a compliant reader concludes each 1920 wide eye should display
3840 wide, derives a 2:1 sample aspect and stretches the picture to 64:9. Both
have to be set.

What to set them to is covered in
[StereoMode display dimensions](#stereomode-display-dimensions) further down,
and the answer is not the one a plain reading of the spec gives. The
specification notes say `DisplayWidth`/`DisplayHeight` are the dimensions of one
plane, which would be 1920x1080. Writing that produces a file Jellyfin on a
Shield refuses to start. 3840x2160 is what works and what BD3D2MK3D has written
for years.

To repair a file made by another tool, no re-encode needed:

```sh
mkvpropedit file.mkv --edit track:v1 \
  --set stereo-mode=1 --set display-width=3840 --set display-height=2160
```

## Subtitle timing, and why .sup inputs need an offset

FFmpeg rebases every input file so that its own first timestamp becomes zero.
The rebuilt subtitle files are separate inputs, so a film whose first subtitle is
44 seconds in had its entire subtitle track shifted 44 seconds early.

Nothing about the resulting file looks wrong under any structural check. The
container is valid, the track is present, the count is right. It was found by
watching Avatar.

Every rebuilt `.sup` is therefore passed with `-itsoffset` equal to its own
`start_time`, which puts back exactly what FFmpeg is about to subtract. Measured
against a synthetic `.sup` starting at 44s: 0.000 without it, 44.000 with it.
The first subtitle in the output is compared against the first in the rebuilt
track after every encode, and a drift above one second is a warning.

## Colour tagging

The filter chain starts with
`setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv`.

The Y4M coming out of the decoder carries no colour tags. Asking for bt709 on
the output is a conversion request to FFmpeg 8, not a labelling one, and
converting transfer characteristics means going through linear light, so
swscale routes every frame through 16-bit RGB. It announces itself as:

```
No accelerated colorspace conversion found from yuv420p to bgr48le
```

That is a full YUV to RGB and back on every frame, and it lands hardest in dark
gradients, which is exactly what 10-bit is for. `setparams` labels the frames
instead, so input and output already agree and nothing is converted.

It only shows up at 10-bit, because at 8-bit the pixel format does not change
and no scaler is inserted at all. If you see that warning in your own FFmpeg
work, the fix is almost never a `format` filter.

## Sources on a NAS

Extraction is network-bound and encoding is CPU-bound, so they barely compete.
You can extract the next film while the current one encodes:

```sh
mvc2sbs --extract-only movie2.mkv    # in another terminal, during an encode
mvc2sbs --keep-temp movie2.mkv       # later, reuses the scratch, no network
```

The scratch stream is never written to a network share. It defaults to the
output directory, but falls back to local storage if that is a network volume,
because the decoder memory-maps it and reads it continuously.

## Length verification

After a full encode the source and output video durations are compared and a
warning is printed if they differ by more than a second. A dropped or duplicated
frame during decode would silently put the video out of sync with the
stream-copied audio, and finding that out after a three hour encode is
miserable.

## StereoMode display dimensions

A Full-SBS file declares display dimensions of 3840x2160, not the per-eye
1920x1080 that a plain reading of the Matroska spec suggests. Both express the
same 16:9 ratio, so the picture looks correct either way, but Jellyfin on an
Nvidia Shield refuses to start a file carrying the smaller value and plays the
same file carrying the larger one. Declaring a display smaller than the coded
frame reads as a request to scale down, and a server can decide against direct
play on that basis. BD3D2MK3D has written 3840x2160 for years.

Files produced before this was fixed can be corrected in place, no re-encode:

```sh
mkvpropedit FILE --edit track:v1 --set display-width=3840 --set display-height=2160
```

## Why MKVToolNix writes the output

FFmpeg encodes to a staging file and `mkvmerge` produces the file you keep.

Both write valid Matroska with identical streams. Every field `mkvdiff` checks
agrees between them: codec, profile, level, resolution, pixel format, colour
tags, aspect, StereoMode, display dimensions, track layout, duration, cues.
Jellyfin's Android TV client on an Nvidia Shield nonetheless refuses to direct
play the FFmpeg file and plays the mkvmerge one. That was established by
remuxing a single file with `mkvmerge -o new.mkv old.mkv`, changing nothing
else, and watching it start. BD3D2MK3D has always muxed with mkvmerge, which is
why files from it never showed the problem.

The cost is rewriting the file once at the end of the encode: minutes against
hours. Without mkvtoolnix installed `mvc2sbs` refuses to start, rather than
spending an encode on a container that may not play. `MVC2SBS_ALLOW_FFMPEG_MUX=1`
overrides that for anyone who genuinely wants FFmpeg's file.

## Inverted depth

If a film is uncomfortable to watch and depth feels wrong without the picture
being obviously broken, the eyes may be the wrong way round.

```sh
mkvdiff --eyes FILE
```

It measures horizontal disparity between the two halves and reads the StereoMode
flag, because the two together decide what a viewer sees. Two parallel cameras
give `x_left - x_right = f*b*(1/Z - 1/Zc)`: nearer than the screen is positive,
further is negative, and films keep most of the frame at or behind the screen.
A file flagged right-eye-first wants the opposite sign.

The fix usually costs nothing:

```sh
mkvpropedit FILE --edit track:v1 --set stereo-mode=11
```

That changes how a player reads the halves without touching a pixel. Jellyfin on
an Nvidia Shield honours it, measured. `mvc2sbs --swap-eyes` rebuilds the frame
itself and is only needed for a player that ignores the flag, at the cost of a
full re-encode.

## Repairing a file made by an older version

Files made before 3.41 report `field_order` as unknown rather than progressive.
mkvmerge writes the interlacing flag as undetermined and an HEVC bitstream gives
a reader nothing to fall back on.

This is tidiness, not a fault. A file with the flag unset direct plays on a 2017
Shield, measured. Fix it in place if you want the file to say what it is, no
re-encode:

```sh
mkvpropedit FILE --edit track:v1 --set interlaced=2
```


Files produced before the mux moved to MKVToolNix carry two container faults:
FFmpeg wrote the container, and FFmpeg wrote the chapters with end times. Both
are fixable without re-encoding.

```sh
mkvdiff --repair "Your Film.mkv"
```

It re-muxes with mkvmerge, drops the chapter end times, and restores StereoMode
and the display dimensions. A three hour film takes a few minutes.

To find which of your files need it:

```sh
mkvdiff FILE | grep -E "writing_app|ordered_hint"
```

`Lavf` as the writing application, or `YES` for the ordered-chapter hint, means
repair it.

## Chapters, and why FFmpeg must not write them

This one cost an evening, so it is worth stating plainly.

FFmpeg's Matroska muxer writes a `ChapterTimeEnd` on every chapter. Matroska
only gives that element meaning for ordered editions, where the player is
supposed to build a virtual timeline out of the chapter ranges instead of
playing the file straight through. Players that take the hint hand you a broken
timeline. Measured on one feature, all three from the same file:

| Player | Symptom |
| --- | --- |
| VLC (macOS) | no video window at all for the first 47 seconds, then normal |
| Kodi (Shield) | audio immediately, video only after skipping forward |
| Jellyfin (Shield) | refuses to start at any position |

Every one of them plays the same file once the chapters are rewritten without
end times. MKVToolNix omits the element, which is why files from BD3D2MK3D and
anything else muxed with mkvmerge have never shown this.

So `mvc2sbs` passes `-map_chapters -1` to FFmpeg and hands the chapters to
`mkvmerge` during the remux above, stripping `ChapterTimeEnd` on the way
through. This needs mkvtoolnix installed, and `mvc2sbs` checks before any work
starts rather than discovering it after a three hour encode.

Check any file with:

```sh
mkvdiff FILE | grep chapters_ordered_hint
```

`YES` means the file carries the element and may misbehave. Fix an existing file
in place, no re-encode:

```sh
mkvextract IN.mkv chapters | sed '/ChapterTimeEnd/d' > ch.xml
mkvpropedit OUT.mkv --chapters ch.xml
```

Note that this fault is invisible to every other check. Duration, cues,
keyframes, bitrate, colour tags and stream layout are all correct on an
afflicted file, and the picture and sound in it are perfect.

## Testing settings against each other

Cut one short clip from the source first, then encode that clip with each
setting. Do not use `--start` for this.

```sh
mkvmerge -o clip.mkv --split parts:00:26:30-00:27:30 SOURCE.mkv
mvc2sbs --info clip.mkv          # confirm the MVC view survived the cut
```

Three reasons it is better than `--start` on the full source:

- Every encode begins on exactly the same frame. `--start` snaps to the nearest
  keyframe, and two runs that begin on different frames produce a meaningless
  PSNR while looking perfectly valid.
- The elementary stream is extracted once instead of once per test.
- The clip is a few hundred MB, so it lives on local disk rather than the NAS.

Then run each setting against the clip with no seeking involved:

```sh
mvc2sbs --x265 --10bit -q 18 -p slow -o t-q18.mkv clip.mkv
mvc2sbs --x265 --10bit -q 20 -p slow -o t-q20.mkv clip.mkv
mkvdiff --quality t-q18.mkv t-q20.mkv
```

Pick the section deliberately. A film's opening is usually its cheapest minute,
and settings that look identical there can diverge badly in motion. `mkvdiff
--peak SOURCE.mkv` shows where the expensive parts are.

And one that cost the most time of anything in this project: **two faults at
once will make a correct single-variable test look like an exoneration.** The
chapter fault was tested in isolation, cleanly, and cleared, because the
display-dimension fault was still there underneath it and producing the same
symptom. If a change that should have worked did not, consider that you may be
looking at two things rather than one.

## x265 or VideoToolbox

Measured on one minute of Gravity's busiest section, 3840x1080, each encode
compared against a common x265 CRF 12 reference so the numbers rank against each
other. M1 Pro.

| Encode | Size | PSNR vs ref | SSIM | Time |
| --- | --- | --- | --- | --- |
| x265 CRF 20, `slow`, 10-bit | 178 MB | 46.16 dB | 0.9811 | 6 m 47 s |
| VideoToolbox quality 55, 10-bit | 81 MB | 44.73 dB | 0.9744 | 0 m 16 s |
| **VideoToolbox quality 62, 10-bit** | **192 MB** | **46.45 dB** | **0.9823** | **0 m 15 s** |
| VideoToolbox quality 65, 10-bit | 235 MB | 46.88 dB | 0.9840 | 0 m 16 s |

Quality 62 is the match: marginally better than x265 CRF 20 on both metrics, 8%
larger, and 27 times faster. On the Apple Silicon media engine a feature takes
around 25 minutes. x265 at `slow` runs at 3 fps on this material and would take
most of a day.

(Interpolating from the 55 and 65 points predicted 165 MB for quality 62. It
came out at 192. Interpolation on a quality scale nobody has documented is worth
about that much.)

Two caveats worth more than the table.

**PSNR under-rates x265 by design.** At `slow` it applies psychovisual
optimisation, which deliberately spends bits on detail that looks right rather
than detail that scores well. An encoder doing none of that flatters itself on
PSNR and SSIM. The gap on screen is likely smaller than the numbers suggest, and
may run the other way.

**The reference is not the source.** It is an x265 CRF 12 encode, near
transparent but still lossy. Sharing an encoder family with one of the
candidates should, if anything, favour x265, and VideoToolbox still scored
higher. That makes the result more trustworthy, not less, but a lossless
reference would settle it properly.

So: **VideoToolbox at quality 62 is the recommended setting on this hardware.**
It direct plays on a Shield, and on a 3840x1080 clip played on a plasma it was
indistinguishable from x265 CRF 20. The metrics and the eye agree.

The clip was chosen with `mkvdiff --peak`, which finds the minute that costs the
most bits. On this film that is a quiet two-shot that pans across the night side
of Earth: grain and deep shadow, plus a slow camera move over city lights, which
is small high-contrast highlights on near-black. That covers banding, grain
retention, and motion over fine detail, which is most of what matters.

It is still not a fast-action test. If your material is heavy on rapid cutting
or violent movement, compare a scene like that before converting a library.

## Ranking two encoders properly

`mkvdiff --quality A B` measures how far apart two files are. It does not say
which is better. Comparing an x265 encode against a VideoToolbox one tells you
they differ; it cannot tell you which is closer to the source, because neither
of them is the source.

To rank them, make a near-lossless reference from the same clip and compare each
candidate against that:

```sh
mvc2sbs --x265 --10bit -q 12 -p fast -o ref.mkv clip.mkv
mkvdiff --quality ref.mkv candidate-a.mkv
mkvdiff --quality ref.mkv candidate-b.mkv
```

Now the two numbers are comparable, and the higher one is genuinely closer to
the source. Match the file sizes first if you are comparing encoders rather than
settings, otherwise you are measuring the bitrate you chose.

## Is CRF 18 actually better than CRF 20

```sh
mkvdiff --quality t-hard-q18.mkv t-hard-q20.mkv
```

Reports PSNR and SSIM between two encodes of the same footage. Above 45 dB they
are near enough identical that a visible difference is very unlikely, and you
should take the smaller file. Below 35 dB the lower CRF is doing real work.

Both files must be the same resolution and duration, so cut them with the same
`--start` and `--limit`.

## Updating

```sh
./install-mac3d.sh --scripts-only
```

Run it from the folder you just unpacked, and check the version it reports.
macOS unpacks a second copy of an archive as `mvc2sbs-mac 2` rather than
replacing `mvc2sbs-mac`, so it is easy to re-run the installer out of the old
folder, see it succeed, and get nothing. The installer names the folder it is
installing from and warns if that would downgrade what you already have.

To see every copy you have and what version each is:

```sh
grep -m1 '^VERSION=' ~/Downloads/mvc2sbs-mac*/mvc2sbs
mvc2sbs --help | head -1      # what is actually on your PATH
```

## Which build made this file

Every output carries the version and settings that produced it:

```sh
mkvdiff FILE | grep mvc2sbs
```

```
  mvc2sbs.version        mvc2sbs 3.5
  mvc2sbs.settings       fsbs x265 crf18 slow 10bit subs3d(depth0,bright1.0,source)
```

`not stamped` means the file predates 3.5 or was not made by this tool. Files of
unknown provenance are worse than no files: comparing two of them produces
confident conclusions about the wrong variable.

## Diagnosing a file a player refuses

`mkvdiff` prints the fields a hardware decoder actually cares about and marks
what differs between two files:

```sh
mkvdiff known-good.mkv suspect.mkv
```

If you have output from another tool that plays on the same hardware, comparing
against it finds the offending field far faster than reasoning about it.

## Known limitations

1. **Disc and ISO input.** MakeMKV MKV files only. Rip first.
2. **Half layouts get 2D subtitles.** The bitmaps would need rescaling.
3. **No per-scene subtitle depth.** BD3D2MK3D reads the disc's 3D-plane depth
   metadata; MakeMKV does not preserve it, so `--sub-depth` applies one fixed
   disparity for the whole film.
4. **Interlaced sources fail.** edge264 does not support PAFF or MBAFF. 3D
   Blu-rays are progressive, so this should never come up.
5. **8-bit sources only**, which is all MVC Blu-ray ever was. You can still
   encode a 10-bit output.
6. **No forced-subtitle detection, track naming or cropping presets.** This is a
   converter, not a project manager.

## Troubleshooting

**Warnings that are expected and harmless.** `sps_id N out of range` is
FFmpeg's 2D H.264 parser complaining about the MVC subset SPS while copying it
through untouched. `Invalid Block Addition value 0x0 for unknown Block Addition
Mapping type 6d766343` is `mvcC`, the MVC configuration record MakeMKV attaches
to the track. `Starting new cluster due to timestamp` is routine muxer chatter.

**"Decoder returned a single view".** Run `--info`. If the NAL histogram shows
no type 15 and type 20 entries, the rip has no second view: re-rip with the
Mpeg4 MVC track ticked. If those NAL types are present but only one view comes
out, that is a decoder bug rather than a bad rip.

**Is the preview really stereo?** Do not rely on your eyes. `--preview` reports
the PSNR between the two halves. `inf` means they are pixel-identical and the
dependent view did not decode. A real stereo frame with foreground detail lands
15 to 30 dB. Above roughly 45 dB the frame simply has very little depth, which
is normal for logos, titles, fades and distant scenes.

**Decoder crashes or stalls.** Some discs carry unusual NAL units. `-k` is
already passed to skip them; if it still dies, add `--single-thread`.

**Output plays as a squashed 2D image.** The player is ignoring StereoMode. Set
the 3D mode manually.

**Black screen, or no picture until you seek forward.** Almost always the
chapters. See the chapters section above.

## Development

```sh
python3 tests/test_pgs3d.py    # builds a synthetic PGS stream and verifies it
shellcheck -S warning mvc2sbs mkvdiff mkvshrink install-mac3d.sh app/build-app.sh
cd app && ./build-app.sh       # builds the app, fetching the decoder if needed
python3 -m pip install pillow  # only needed to regenerate the icon
python3 app/make-icon.py       # regenerates MVC2SBS.icns
```

CI runs the shell and Python checks, the PGS test, and a full macOS app build on
every push. The app build is the valuable one: it is the only way to catch Swift
compile errors without a Mac to hand.

The app is a front end only. Every conversion runs through `mvc2sbs`, which
emits machine-readable `@@` status lines on stdout when given `--machine`, so
the GUI parses structured output rather than scraping human text.

## Credits and sources

This project is a thin orchestration layer. The genuinely hard parts were solved
by other people.

- **[edge264](https://github.com/tvlabs/edge264)** by Thibault Raffaillac and
  Celticom/TVLabs, and the
  **[MVC fork](https://github.com/cbusillo/edge264-mvc)** by Chris Busillo and
  Jens Duttke. The only open source MVC decoder that runs natively on Apple
  Silicon, and the reason this project can exist.
- **[BD_to_AVP](https://github.com/cbusillo/BD_to_AVP)** by Chris Busillo. A
  macOS 3D Blu-ray converter targeting MV-HEVC for Apple Vision Pro. Its use of
  edge264 is what showed this approach was viable. Worth using directly if
  Vision Pro rather than a 3D TV is your target.
- **[BD3D2MK3D](https://www.videohelp.com/software/BD3D2MK3D)** by r0lZ. The
  Windows original this replaces. No code was taken from it, but it defined what
  the output should look like, and its conventions are why CRF 16 and Full-SBS
  are the defaults here.
- **[FFmpeg](https://ffmpeg.org)**, **[x264](https://www.videolan.org/developers/x264.html)**,
  **[x265](https://www.x265.org)** and **[MKVToolNix](https://mkvtoolnix.download)**
  do the demuxing, encoding and muxing.
- **[MakeMKV](https://www.makemkv.com)** produces the source files.

Specifications referenced while building this:

- [RFC 9559, Matroska Media Container Format](https://www.rfc-editor.org/rfc/rfc9559.html)
  and the [Matroska specification notes](https://www.matroska.org/technical/notes.html),
  for StereoMode and display dimension behaviour.
- The Blu-ray PGS subtitle format, for the segment structure `pgs3d.py` rewrites.
- [ITU-T H.264 Annex H](https://www.itu.int/rec/T-REC-H.264), for MVC NAL types
  15 and 20.

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for licences.

## Licence

MIT. See [LICENSE](LICENSE).

FFmpeg and MKVToolNix are invoked as separate processes rather than linked
against, so their licences do not constrain this project's code. edge264 is
bundled into the built app and is BSD licensed, which requires its copyright
notice to travel with any redistributed binary. That notice is in
THIRD-PARTY-NOTICES.md.
