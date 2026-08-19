# mkvshrink

Re-encodes existing MKV files to HEVC to reclaim disk, and drops audio and
subtitle tracks that will never be played. Companion to `mvc2sbs`: different
job, same hard-won rules.

Requires `ffmpeg`, `ffprobe`, `mkvmerge`, `mkvpropedit`, `mkvextract` and
`python3`. Looks for `mkvdiff` in its own directory, so keep the three tools
together.

## Quick start

```
mkvshrink --keep-originals film.mkv                 # one file, original untouched
mkvshrink --plan plan.tsv /Volumes/Media/Films      # review before committing
mkvshrink --apply plan.tsv
mkvshrink --luma /Volumes/Media/Films               # triage, encodes nothing
mkvshrink --calibrate film.mkv --keep-clips         # settings, judged by eye
```

`--plan` takes the plan filename first, then the paths to scan. It does not
write to stdout.

## How it decides

Gates run cheapest first:

| Gate | Default | Reason |
| --- | --- | --- |
| min size | 5G | A small file is small because it was already encoded at a low bitrate, so the encode inflates it. Rejecting it after three probe encodes wastes the probes. |
| already HEVC | skip | Nothing to gain. |
| HDR, interlaced | skip | Untested paths, deliberately excluded. |
| probe | 3 windows | Metadata cannot predict the saving. How much HEVC wins depends on how tightly the source was already encoded. |
| min PSNR | 40 dB | See "PSNR is not a quality gate" below. Consider running with `--min-psnr 0`. |
| min saving | 10% | Measured against the free lossless remux, not against doing nothing. |

Probe accuracy measured against actual output: Akira predicted 51.9% and
delivered 55.7%; GoodFellas predicted 67.0% and delivered 57.8%. Treat the
prediction as plus or minus 10 points. It is good enough to decide whether to
encode and not good enough to promise a number.

## Track selection

Subtitles: keep `eng`, `en`, `und`; keep any forced track in any language; keep
anything named SDH, CC, Caption or Hearing.

Audio: keep every whitelisted language, and always keep the first audio track
whatever its language.

**The audio rule has a known hole.** It covers a foreign-language film only
when the original language is listed first. On a release that puts the English
dub at track 1 and the original at track 4, the original is neither
whitelisted nor first, and it is dropped. This was found on a scene release of
Akira, where the Japanese track would have been lost.

No metadata reliably identifies a film's original language and `FlagOriginal`
is set on virtually nothing, so the rule cannot be fixed in general. What the
tool does instead is name the loss: any language that loses every one of its
tracks is reported as a warning and recorded in the plan's reason column as
`drops-audio:jpn,spa`. For a Japanese library, pass `--audio-langs eng,en,jpn`.

Consequence: for mixed-language content, plan and review is not optional. A
direct unattended run can still lose original audio.

## PSNR is not a quality gate

Measured across four films, PSNR did not predict what the eye saw.

| Film | PSNR | Ratio | Verdict |
| --- | --- | --- | --- |
| A Silent Voice (2016) | 47.4 | 0.06 | clean, 72.5% saved |
| Akira (1988) | 46.8 | 0.48 | clean over an hour, 55.7% saved |
| Princess Mononoke (1997) | 35.2 | 0.66 | clean |
| Blade Runner 2049 (2017) | ~39 | 0.27 | crushed blacks, banding |

The only failure scored higher than a film that was fine. Low PSNR on grainy
content means the grain pattern differs, which is invisible. PSNR is also close
to blind to banding, because the error is small in magnitude and spread across
a large flat area, which is exactly what the metric averages away.

Two signatures appear to differ, on limited evidence:

- **low ratio and low PSNR**: compresses easily because dark flat gradients
  hold little detail, then bands because those gradients had no headroom left
  in 8-bit. Blade Runner 2049.
- **high ratio and low PSNR**: barely compresses because grain is
  high-entropy noise, and scores badly because grain is not reproduced exactly.
  Usually invisible. Princess Mononoke, GoodFellas, Saving Private Ryan.

This is a hypothesis from four films, not an established rule.

## --luma

Profiles how much of the code range a film uses, without encoding anything.
About a minute per film, seeks only.

Banding is not caused by darkness as such. It is caused by crowding: if most of
a frame sits between luma 16 and 60 then about 44 code values carry the whole
picture, and re-quantising them shows as steps. A dark frame that still spans a
wide range has room to spare. The reported `risk` is the share of sampled
frames that are both dark (YAVG under 60) and narrow (YHIGH minus YLOW under
60), normalised to an 8-bit scale so 8-bit and 10-bit sources compare directly.

Measured:

| Film | risk | Verdict |
| --- | --- | --- |
| A Silent Voice | 5% | clean |
| Princess Mononoke | 25% | clean |
| GoodFellas | 37% | under test |
| Blade Runner 2049 | 44% | damaged |

**A low score is trustworthy and a high score is only a flag.** Nothing dark
and narrow means nothing to band, so low-scoring films need no visual check.
High-scoring films need looking at, but 25% and 37% have not failed. The
boundary between 25 and 44 is unknown, so treat anything above roughly 20% as
worth a look and tighten that as results accumulate.

This does not separate the films cleanly enough to be an automatic gate. It is
a triage tool that reduces how many files need eyes on them.

## Calibration

`--calibrate` cuts one clip and encodes it at several settings, reporting size,
PSNR, SSIM and time against the source clip. By default it finds the darkest
point in the film, since that is where banding shows. `--keep-clips` retains
the encodes so they can be compared by eye, which is the only reliable way to
judge banding.

Measured on Blade Runner 2049, a hard case:

| Encode | Size | PSNR | SSIM | Time |
| --- | --- | --- | --- | --- |
| vt 55 10-bit | 11% | 39.30 | 0.9641 | 9s |
| vt 62 10-bit | 27% | 39.86 | 0.9719 | 9s |
| vt 65 10-bit | 33% | 39.99 | 0.9738 | 10s |
| vt 70 10-bit | 69% | 40.49 | 0.9813 | 10s |
| x265 CRF 20 10-bit | 25% | 39.78 | 0.9715 | 3m45s |
| x265 CRF 18 10-bit | 38% | 40.09 | 0.9759 | 4m22s |

Quality 62 sits on the knee. Above 65 is waste. x265 CRF 20 is marginally
smaller and marginally worse than VideoToolbox 62 for twenty-five times the
time, which confirms VideoToolbox as the right default for a library sweep.

A flat curve like this one means bitrate is not the limit and the content is.
Two encoders with completely different architectures landing within a quarter
of a decibel of each other is the content speaking, not the encoder.

## Machine output

`--machine` emits structured events for a GUI to consume:

```
@@progress file=NAME pct=63.4 fps=184 speed=7.66 eta=319 elapsed=652
@@sweep index=23 total=60 elapsed=8100 done_bytes=... todo_bytes=...
@@done PATH SAVED
@@summary DONE SKIPPED FAILED
```

The console display is a consumer of the same data, so neither owns it.

## Plan format

Tab-separated. Columns: action, audio, subs, save%, psnr, ssim, risk, size_mb,
pred_mb, uid, path, reason.

Plans written before the ssim and risk columns existed have ten columns and
still apply: the shape decides how a row is read, not the build that wrote it.

`risk` is the banding score `--luma` computes, as a percentage: the share of
sampled frames that are both dark and low in contrast. It is the one number
here that has matched what the eye saw. Measured at `--risk-samples` frames per
file while planning, and only for files something would be done to.
`--no-risk` turns it off.

Edit the action, audio and subs columns; delete rows to exclude them. Rows are
matched to files by segment UID and by size as well as by path, so a plan that
has gone stale is refused rather than applied to the wrong tracks.
`--allow-changed` overrides the size check. Applying a plan written by a
different build warns, because the rules and the arithmetic have both changed
between builds.

Sort by saving to find where the disk is. Sort by reason to find what was
skipped and why. Sort by risk to find what is worth watching afterwards.

`--tracks FILE` prints the same track table tab separated, one line per track,
with the keep decision the current rules would make. That is what the GUI reads
to offer a track back that the rules dropped.
