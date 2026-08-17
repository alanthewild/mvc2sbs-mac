# Contributing

Bug reports about specific discs are the most useful thing you can send. This
was developed against a small number of titles, and the subtitle transform in
particular has only met a handful of real Blu-rays.

## Reporting a disc that does not work

Run this and paste the output:

```sh
mvc2sbs --info "Your Film.mkv"
```

That prints the track list, a NAL type histogram from the first 20 seconds of
the bitstream, and whether both views decode. It touches nothing and takes a few
seconds.

If the video converts but the result does not play somewhere, compare it against
a file that does play on the same hardware:

```sh
mkvdiff known-good.mkv suspect.mkv
```

If subtitles are the problem, say which disc, roughly where in the film, and
whether the failure is position, timing, colour, or subtitles vanishing during
fades. Fades use palette-only updates, which is the part of the PGS transform
most likely to have gaps.

## Before opening a pull request

```sh
python3 tests/test_pgs3d.py
shellcheck -S warning mvc2sbs mkvdiff install-mac3d.sh app/build-app.sh
cd app && ./build-app.sh
```

CI runs all three on every push, including the macOS app build.

## Conventions

- `mvc2sbs` is POSIX-ish bash with `set -euo pipefail`. Keep shellcheck clean at
  warning level.
- Every long-running child process must be interruptible. Bash does not service
  traps while blocked on a foreground child, so anything slow goes through
  `run_interruptible` or is backgrounded and waited on. Cancel has to work.
- The app is a front end. Conversion logic belongs in `mvc2sbs`, which can be
  tested; the Swift layer parses `@@` status lines and draws things.
- Prefer measuring a claim to arguing it. Several decisions here, the banding
  numbers, the subtitle brightness gamma, the aspect ratio bug, came from a
  small script that produced a number, and those scripts are worth keeping.
