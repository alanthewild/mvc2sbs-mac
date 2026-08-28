# Working notes for Claude

Read this first, then `README.md`. This file holds the working agreement and
the conclusions that were expensive to reach. The repository is the memory:
nothing important should live only in a conversation.

## The project

`mvc2sbs-mac` converts 3D Blu-ray MVC to Full-SBS on macOS, natively, as a
replacement for BD3D2MK3D. Four command line tools and two SwiftUI apps:

| | |
| --- | --- |
| `mvc2sbs` | MVC to Full-SBS conversion, including 3D subtitles |
| `mkvdiff` | Compares two MKVs field by field. The diagnostic tool |
| `subs3d` | Adds 3D subtitles to a Full-SBS film that has none |
| `mkvshrink` | Sweeps a library, re-encoding H.264 to HEVC to reclaim disk |
| `pgs3d.py` | The PGS subtitle transform, used by the above |
| `app/` | MVC2SBS.app |
| `app/shrink/` | MKVShrink.app |

Alan is the author and the only user. He runs it on an M1 Pro against a
Jellyfin server, an NVIDIA Shield TV (2017) and a Panasonic VT60 plasma.
Every playback claim in the docs was measured on that setup.

## How we work

**Batches, not releases.** Changes accumulate under `## Unreleased` in
CHANGELOG.md. Nothing is versioned until Alan says "ship it". Then, in one go:

1. Bump `VERSION` in `mvc2sbs`, `mkvdiff`, `subs3d` and `mkvshrink`, and
   `BUILD` in `mkvshrink`. All four must match or `test_version.py` fails.
2. Rename the `## Unreleased` heading to the new version.
3. Run every test.
4. Commit as one change.
5. Build the tarball, which must unpack to `mvc2sbs-mac/`. Renaming that
   folder breaks his install command.

**No em-dashes in anything written.** They read as machine-written. This
applies to documentation, comments, commit messages and replies.

**Answers are short and direct.** Say what is wrong, say what was done. No
softening, no restating the question back.

**Tests are written after faults, not before features.** Every file in
`tests/` exists because something broke. When fixing a bug, add the test that
would have caught it, and verify it fails without the fix. Nothing here can
compile Swift, so `test_swift_structure.py` lints it instead, and
`test_shrink_gui.py` checks the interface between the GUI and the script,
which is where a GUI driving a command line tool actually breaks.

**Claims are measured or they are labelled as guesses.** Several confident
paragraphs in this README turned out to be wrong, and each one cost hours of
chasing the wrong variable. If something has not been measured on the hardware
above, the text says so.

## Conclusions that should not be relitigated

These were each established the hard way. Changing anything that depends on
them needs a new measurement, not an argument.

- **Mux with MKVToolNix, never FFmpeg.** FFmpeg's output and mkvmerge's
  contain identical streams and agree on every field `mkvdiff` checks, and the
  Shield refuses to direct play FFmpeg's.
- **Never let FFmpeg write chapters.** It writes a `ChapterTimeEnd` on every
  chapter. Matroska only defines that for ordered editions, and a player that
  reads it as one shows no picture until the first chapter boundary.
- **Full-SBS must declare a 3840x2160 display size**, not the per-eye
  1920x1080 that a plain reading of the spec suggests. Both express 16:9, and
  Jellyfin refuses a file whose declared display is smaller than its coded
  frame. Each eye is still 1920 wide, which is what a Blu-ray player does.
- **mkvmerge exit code 1 is warnings, not failure.** Treating it as failure
  throws away finished work over a note about a track header. This was fixed
  twice, in `mvc2sbs` and later in `mkvshrink`.
- **FFmpeg rebases every input so its own first timestamp becomes zero.** A
  rebuilt `.sup` therefore needs `-itsoffset` or subtitles arrive at 0s
  instead of 44s.
- **ExoPlayer reads composition object 0 only.** Duplicating the PGS
  composition object puts a subtitle in the left eye and nothing in the right
  on a Shield, while VLC shows both. The two eyes must be spliced into one
  bitmap.
- **libass composites with premultiplied alpha.** The red channel is the fill
  coverage and the black outline reads as zero. Thresholding red throws the
  antialiasing away.
- **PSNR is a weak signal, not a quality gate.** Across five films it did not
  predict what the eye saw. It is close to blind to banding, which is a small
  error spread over a large flat area, which is what an average hides. The
  banding `risk` score is the number that has actually matched.
- **H.264 High 10 is refused by the Shield**, "the video codec's profile is
  not supported", and transcoded. HEVC Main 10 plays. Anime releases use High
  10 constantly, so converting one is worth doing at any saving.
- **Two faults at once make a correct single-variable test look like an
  exoneration.** The original "no HEVC variant plays" conclusion came from
  four files that all shared two unrelated defects.

## Commands

```sh
# tests, all of them, before any commit
for t in tests/*.py; do python3 "$t" || echo "FAIL $t"; done
bash tests/test_install.sh
shellcheck -S warning mvc2sbs mkvdiff mkvshrink install-mac3d.sh

# apps. --install also copies the bundle into /Applications, which is what
# Alan runs, so a build without it changes nothing he can see.
cd app && ./build-app.sh --install && ./build-shrink.sh --install

# icons, only if changing them, needs Pillow
python3 app/make-icon.py

# install to ~/.local/bin
./install-mac3d.sh
```

## Constraints

- **No third party Python.** The tools must run on a stock macOS with nothing
  installed but Homebrew's ffmpeg and mkvtoolnix. `test_no_third_party_python.py`
  enforces this. Pillow is allowed in `make-icon.py` alone, which is a
  developer tool and never runs at conversion time.
- **No `realpath`.** Not present on a stock macOS.
- **The plan file is a positional interface.** `mkvshrink` writes it and
  MKVShrink.app reads it, both by column number. Adding a column to one side
  and not the other does not fail loudly: it puts one column's number under
  another's name. `test_shrink_gui.py` checks both sides agree.
