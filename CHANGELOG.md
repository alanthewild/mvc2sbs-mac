# Changelog

## 3.62

- The movable divider is on the track panel, where it was wanted, not between
  the file pane and the settings pane. That top split is back to a fixed third
  and two thirds.
- **Sources, Audio and Subtitles all have draggable widths now**, remembered
  across restarts, with a double click on either divider putting that column
  back to its default. How much room each needs depends on the disc: long
  filenames want a wide Sources list, fourteen audio tracks want a wide middle,
  and fixed thirds suit neither.
- Each column has a minimum so a split saved on a wide display cannot leave one
  unusable on a narrow one.


## 3.61

- **mkvshrink lives here now.** It is a separate pipeline, not a 3D tool, but it
  inherits every rule this project paid for and some of the files it will be
  pointed at are the side-by-side conversions mvc2sbs produced. One repository,
  one set of rules, one test suite.
- It keeps its own VERSION and BUILD rather than sharing the number the 3D tools
  move together on. Two pipelines with separate cadences sharing one number
  means bumping it when nothing in that tool changed, which destroys the only
  thing a version is for. test_version.py now checks that mkvshrink has both and
  stamps them into its output, which is the property that actually matters.
- Installed by install-mac3d.sh, linted by shellcheck in CI, and covered by the
  standard-library check and the installer test.
- **Shellcheck found a real gap on the way in.** `PE_PROBES` counted how many
  probe windows survived and was then never read. It is in the report line now:
  a prediction drawn from one surviving window is a much weaker claim than the
  same numbers from three, and nothing in the output said which you had.


## 3.60

- The divider between the file pane and the settings pane is draggable, and
  where you put it is remembered across restarts. Double click resets it to a
  third. The grab area is ten points wide though the line stays one, because a
  one pixel target is a test of aim rather than a control.
- The width is clamped on the way out as well as on the way in, so a position
  saved on a wide display cannot leave a pane unusable on a narrow one.


## 3.59

- The track panel is the same height whatever is loaded. Both halves of the
  window were flexible, so SwiftUI split the space by how much content each
  happened to hold: half the window with nothing selected, a third with a file
  in. The split is now measured from the window, 28% for the tracks and the
  rest for the settings, so adding a file no longer moves everything.


## 3.58

- Reset Defaults is now "Reset to Defaults" and asks first. It sits next to a
  picker people change often, and one stray click should not be able to throw
  away a carefully set up job. The confirmation says what it is about to apply
  and that the destination and file name are left alone.


## 3.57

- The right pane always shows a Saving to row, with the Destination button on
  it. With nothing selected it says "No file selected" rather than vanishing: a
  control that comes and goes is harder to find than one that stays put.
- The "Defaults for new files" heading is gone, and so is the duplicate Reset
  button left behind in the Tools sheet when Reset Defaults moved out beside the
  Format picker. The note about where settings are stored stays, since that is
  worth knowing and is not a control.


## 3.56

- **subs3d renders PGS as well as ASS, and writes both by default.** No single
  subtitle format plays everywhere, so the file carries a bitmap track for the
  players that want bitmaps and a text track for the ones that want text, and
  the player picks. The mux is free either way: nothing is re-encoded.
- The PGS renderer draws each line with libass onto a transparent canvas, turns
  the result into a palette index per pixel, and runs it through the same pgs3d
  path that now works on a Shield, so it comes out as one bitmap spanning both
  eyes. No pixel is examined in Python: the index is built with
  `bytes.translate` and combined with big integer masking, both in C.
- **Antialiasing very nearly did not survive.** libass composites with
  premultiplied alpha, so the red channel of a white glyph is already coverage
  times 255 and a black outline reads as 0 however opaque it is. Thresholding
  red at 128 put every soft edge of the text into the outline ramp and
  collapsed the fill to a single opaque shade. Red is the fill coverage, and
  red above 0 is the test for fill. Now 127 shades in each ramp, checked.
- The synthetic render timeline also had to line up with whole seconds: cues
  drawn from 0.25 to 0.75 of each second fell between frames at 1 fps and every
  line rendered blank.
- subs3d is a Python tool now rather than a shell script wrapping Python, so the
  ASS writer and the PGS renderer share one parser instead of two.
- GUI: the eye order verdict moved to the left pane under the file it is about,
  the Output heading is gone, Advanced Video Settings moved to the toolbar after
  Console, Settings is now Tools, and Reset Defaults sits beside the Format
  picker instead of being buried in a sheet.
- **The help is an index and a page** rather than one long scroll, 14 sections
  down the left, the selected one on the right. A test checks that no two
  sections share a title and no two rows in a section share a heading, since
  either would silently break selection or drop a row.


## 3.55

- `subs3d --help` lists what it needs and when: python3 always, ffprobe and
  mkvmerge only for `--mux`. Both are now checked before any work happens
  rather than discovered at the end, and the error names the brew command.
- A note on fonts, which is the other thing that bites: the font named in the
  file has to exist on whatever plays the film, not on the Mac that made it.
- test_version.py covers subs3d too, so it cannot drift out of step.


## 3.54

- **New tool: `subs3d`.** Adds subtitles to a side-by-side or top-and-bottom
  film that has none. Takes an SRT or an existing ASS and writes a 3D ASS, each
  line drawn twice and positioned in the centre of each eye, with `--depth` for
  disparity. `--mux` puts it in the file with mkvmerge, so nothing is
  re-encoded. An input ASS keeps its styles, scaled to the size of one eye, and
  any `\pos` or alignment it already carried is stripped, since two copies
  cannot both sit where the original asked for.
- A player draws an ordinary subtitle once across the whole frame, so on a
  side-by-side file each eye gets half the sentence. That is what this fixes.
- Verified by rendering the result with libass, the same library VLC, mpv and
  Kodi use, and measuring where the ink landed rather than reading the file.
- Caveat, and it is the same wall as everywhere else: ExoPlayer's ASS support is
  partial, so Jellyfin on a Shield will probably ignore the positioning or burn
  the subtitles in, which means transcoding. For that device the answer is PGS,
  which is the next piece of work.


## 3.53

- Help gains three sections at the top: what MVC2SBS is and what it replaces,
  what each of the four tools does and where they live, and what the app adds on
  top of the scripts. The help opened straight into pipeline detail, which is no
  use to anyone opening it for the first time.


## 3.52

- **3D subtitles now render in both eyes on a Shield.** They never did. pgs3d
  duplicated the composition object rather than the bitmap, which is what the
  PGS format is for, and FFmpeg draws every composition object so VLC showed
  both copies and the file looked correct. ExoPlayer, which is what Jellyfin's
  Android TV client decodes PGS with, skips a fixed 11 bytes past the object
  count in `parseIdentifierSection`, reads the x/y of composition object 0 and
  returns a single Cue. Object 1 was silently dropped, so the right eye was
  empty and what you saw there was crosstalk from the left.
- **The two copies are now spliced into one bitmap**, emitted as one object with
  one composition object and one window, which any decoder can draw. The splice
  works on RLE run boundaries rather than pixels: rows are cut apart,
  transparent runs inserted between the copies, original bytes replayed
  verbatim. Nothing is decoded or re-encoded. A worst case feature length track
  converts in 1.5 seconds. Objects too large for one segment are fragmented on
  the way out, and fragmented source objects are reassembled on the way in.
- **`mkvdiff --subs FILE`** answers the question without watching a film. It
  samples four windows rather than demuxing 30 GB, reports the composition
  object count per display set and whether the first object's bitmap actually
  spans both halves of the frame, and gives a plain verdict. Verified to call
  the old style track broken and the new one correct.
- Cropping is now ignored rather than carried, matching what FFmpeg does. A
  disc has already been seen setting the flag with no rectangle behind it.


## 3.51

- Help note: a Full-SBS file looks squeezed in VLC, and that is correct. The
  3840x2160 display dimensions are what make a Shield accept the file; VLC
  renders the whole frame flat into that 16:9 box, so each eye ends up half
  width. Confirmed on two known-good files. Worth writing down, because it
  looks exactly like a real aspect ratio fault and it is not.

## 3.50

- **Subtitles no longer start at zero when the first one is minutes in.** FFmpeg
  rebases every input file so its own first timestamp becomes zero, and the
  rebuilt subtitle files are separate inputs. On Avatar the first subtitle is 44
  seconds in, so the entire track ran 44 seconds early for the whole film. The
  encode now passes `-itsoffset` equal to the file's own start time, which puts
  back exactly what FFmpeg is about to subtract. Confirmed against a synthetic
  .sup: 44s went in, 0.000 came out, and 44.000 with the fix.
- **A post-encode subtitle check.** First subtitle in the output against first
  subtitle in the rebuilt track, warning above one second. Nothing about the
  broken file looked wrong, which is why it took a viewing to find.
- **mkvmerge warnings no longer throw away the file.** mkvmerge exits 1 for
  warnings and 2 for failure. Every earlier version treated 1 as failure, kept
  FFmpeg's mux instead, and so produced exactly the file that will not direct
  play, losing the chapters and the provenance tags with it.
- **mkvmerge's output is captured and printed.** The failure warning previously
  said only that it failed. It now prints what mkvmerge actually said, which is
  the fourth time in this project that a discarded stderr has cost hours.
- **The elementary stream is deleted as soon as the encode finishes**, not at
  the end of the run. It was previously held through the remux, so the volume
  had to fit the source's worth of H.264, the staging encode and the finished
  file at once: about 100 GB for a 45 GB rip.
- **Free space is checked before the remux**, and reported in GB against what
  the remux needs, while the encode is still safe in the staging file.
- **Every run writes a log** to `~/Library/Logs/mvc2sbs`, one file per run named
  for the source, with colour codes and progress redraws stripped. `--log`,
  `--log-dir` and `--no-log` control it.
- **The console window no longer freezes the app.** SwiftUI's `Text` lays out an
  entire string in one pass and builds selection geometry for every glyph of it;
  a few hundred thousand characters of log meant tens of seconds of beachball.
  It is an NSTextView now, with Save and Log folder buttons.
- `mkvdiff --repair` takes `--chapters-from SOURCE`, for recovering a file that
  fell back to FFmpeg's mux and therefore has no chapters of its own to carry.
  It also checks free space first and no longer treats mkvmerge warnings as
  failure.

## 3.49

- **Fixed pgs3d crashing on a subtitle whose cropped flag has no crop rectangle.**
  Seen on Avatar. The parser read 8 bytes past the end of the segment, which
  killed the whole track and fell the entire film back to flat 2D subtitles. It
  now trusts the buffer over the flag and clears the bit, so the segment stays
  self-consistent.
- **One bad display set no longer costs the whole subtitle track.** Anything that
  fails to convert is now passed through unchanged, rendering in the left eye
  only, which is worse than 3D and far better than nothing.
- Regression test added, and verified to fail without the fix. It was initially
  appended after `sys.exit(main())` and never ran at all, which is the same
  reports-success-without-checking fault this project keeps finding.

## 3.48

- Help text is selectable, so it can be copied out. So are the Advanced,
  Destination and Settings sheets, which carry paths worth copying.
- Commands in the help are no longer buried mid-sentence. They sit in their own
  monospaced block with a copy button, since a command you cannot select cleanly
  is not much use as documentation.

## 3.47

- **Automatic naming now strips 3D and MVC markers wherever they appear**, not
  only at the end. "Avatar- Fire and Ash (2025).3D.MVC.Disc 1" kept its markers
  because they sit in the middle, followed by the disc number.
- Only tokens delimited by `.`, `-` or `_` are removed, never by a space, so a
  film genuinely called "Spy Kids 3D" keeps its name.
- New `tests/test_clean_name.py`, run in CI: eleven real filenames including the
  ones that must survive untouched, plus a check that the Swift still uses the
  same pattern as the test, so the two cannot drift apart.

## 3.46

- **Every full side-by-side encode now checks its own eye order when it
  finishes**, about two seconds after an hour of work. It is the one fault
  nothing else here could see: a film with inverted depth plays perfectly,
  passes every other check, and is merely uncomfortable to watch.
- The app offers a one-click fix, which sets the StereoMode flag rather than
  re-encoding. It **reports rather than corrects**: the estimate is a heuristic
  about how a scene was composed, and silently inverting a film that was right
  is worse than leaving one that is wrong, because there would be no reason to
  look.
- `mkvdiff --eyes-brief` gives the one-line machine form the check uses, and the
  app now bundles `mkvdiff` so the check exists inside the app at all.

## 3.45

- The app's help gained two sections collecting the diagnostics built over the
  last few days: what each `mkvdiff` mode is for, how to tell inverted depth and
  fix it without re-encoding, how to repair a file made by an older version, and
  how to compare settings without fooling yourself — cut one clip, pick the
  scene deliberately, and rank encoders against a common reference rather than
  against each other.
- `tests/test_swift_structure.py` also lints string escapes. Swift accepts only
  a short list, and these help strings are long and written by hand. Writing the
  check immediately flagged every `\(` interpolation in the project, which is
  valid, so the allowed set now includes it.

## 3.44

- **`mkvdiff --eyes` now reads the StereoMode flag.** It measured pixel disparity
  and assumed left-eye-first, so a file fixed by flipping the flag to 11 still
  reported inverted depth. The measurement was right and the verdict was wrong.
  The flag decides how a player reads the halves and can be changed without
  touching a pixel, so only the two together say what a viewer gets.
- Documented that flipping the flag is the fix to reach for first, since it
  needs no re-encode and Jellyfin on an Nvidia Shield honours it, measured.
  `--swap-eyes` is for players that ignore the flag.

## 3.43

- **Fixed the running-app check reporting the app as running when it was not.**
  It used `pgrep`, which matches process names or command lines rather than
  answering the question that matters. `pgrep -x MVC2SBS` matches anything on the
  system with that name, and `pgrep -f` matches this script's own command line,
  because the pattern being searched for appears in it. It now asks `lsof` who
  has the installed binary open, which cannot self-match and is the actual
  question: is the file about to be replaced in use? Verified in all three
  states: not running, running, and just quit.

## 3.42

- Corrected the wording on the progressive flag. It was written as though an
  unset flag caused playback problems; a file with it unset direct plays on a
  2017 Shield. Setting it is correctness, not a fix for anything observed.

## 3.41

- **Every HEVC file made since the mux moved to MKVToolNix lost its progressive
  flag.** mkvmerge writes the interlacing flag as undetermined, and unlike H.264
  there is nothing in an HEVC bitstream for a reader to fall back on, so
  `field_order` reads as unknown where FFmpeg's muxer had said progressive.
  Correctness rather than a playback fix: a file with the flag unset direct plays
  on a 2017 Shield, so on that hardware it changes nothing. It is still wrong to
  declare undetermined when the answer is known. Both `mvc2sbs` and
  `mkvdiff --repair` now set it explicitly.
  Found because `mkvdiff` flagged the field when comparing a repaired file
  against its original, which is what that comparison is for.
- Existing files are fixable in place, no re-encode:
  `mkvpropedit FILE --edit track:v1 --set interlaced=2`

## 3.40

- **`mkvdiff --eyes` no longer needs numpy.** It shipped depending on it and
  failed on the first real Mac it met: a stock macOS python3 has no numpy, and
  this development container happens to have it. The matcher is plain Python now,
  working at 320 pixels per eye, which is ample for a sign and runs in under two
  seconds. Verified in both directions with numpy deliberately blocked.
- New `tests/test_no_third_party_python.py`, run in CI: no tool may import
  anything outside the standard library. Tests may, since they run in CI rather
  than on a user's machine. Writing it immediately turned up a false positive on
  the prose "from around 52% to around 90%" in a help string, so it now requires
  real import syntax.

## 3.39

- `build-app.sh --install` refuses to install over a running MVC2SBS. The app
  executes mvc2sbs out of its own Resources folder, and bash reads a running
  script lazily by byte offset: overwrite it mid-encode and the shell carries on
  reading the new file from the old position, which can skip whole blocks
  without erroring. `FORCE_INSTALL=1` overrides.

## 3.38

- **mvc2sbs refuses to start if MKVToolNix is not on the PATH it can see.** The
  fallback to letting FFmpeg write the container was decided silently, just
  before the mux, so the only way to find out was to inspect the finished file
  after hours of encoding. That fallback produces a file with no chapters, no
  record of its settings, and a container Jellyfin on a Shield refuses. It is now
  checked before any work starts. `MVC2SBS_ALLOW_FFMPEG_MUX=1` overrides it for
  anyone who genuinely wants that.

## 3.37

- New `mkvdiff --repair FILE`, which rebuilds the container of a file produced
  before the mux moved to MKVToolNix. It re-muxes with mkvmerge, strips the
  chapter end times FFmpeg writes, and restores StereoMode and the display
  dimensions. Nothing is re-encoded, so a three hour film is a few minutes
  rather than another three hours. Verified end to end: an FFmpeg-muxed file
  with ordered-chapter end times and 3D tagging comes out mkvmerge-muxed, with
  the end times gone and the tagging intact.

## 3.36

- **Fixed the stale-bundle check, which could never fire.** It compared the app
  version against `Tools.find("mvc2sbs")`, and `find` prefers the bundled copy,
  while the app version is stamped from that same bundled copy at build time. It
  was comparing the bundle against itself. An app carrying a months-old script
  reported perfect agreement. It now compares the bundled copy against the one on
  the search path, says which is older, and Settings shows both.
- Version comparison is numeric, so 3.9 no longer sorts above 3.10.

## 3.35

- **The app now checks for mkvmerge and mkvextract.** It never did. Without them
  `mvc2sbs` falls back to letting FFmpeg write the container, which is the exact
  thing that made Jellyfin on a Shield refuse a file, and the output carries no
  chapters and no record of what produced it. The app checked for ffmpeg,
  ffprobe and mkvpropedit and simply assumed the two tools the mux depends on.
  Missing them is now a hard warning, not an advisory.

## 3.34

- `mkvdiff --eyes` reads dimensions with the same JSON probe the rest of the tool
  uses. The csv form returned an empty string on a real file with no error at
  all, and there was no sense debugging that when a path proven on every file
  here was already available. If it still fails it now prints ffprobe's own
  output and the command to reproduce it.

## 3.33

- `mkvdiff --eyes` now says what actually went wrong. It printed "could not read
  dimensions" with ffprobe's real error sent to /dev/null, which for a mistyped
  path meant it hid "no such file". That is the third time in this tool that a
  discarded stderr has cost a diagnosis.
- It also rejects an ordinary 16:9 frame up front rather than block-matching two
  halves of a 2D picture against each other and reporting nothing useful.

## 3.32

- The claim that NVIDIA hardware cannot decode H.264 High 10 is now measured
  rather than received. Tested on a 2017 Shield: refused, with Jellyfin
  reporting "the video codec's profile is not supported" and transcoding it,
  which also mangles the aspect ratio. Same conclusion, different standing. The
  wording had the same confidence as the measured claims beside it without
  having earned it.

## 3.31

- New `--swap-eyes`, and a "Swap left and right" toggle beside Format. It
  rebuilds the frame with the right eye first rather than only relabelling it,
  because a TV in manual side-by-side mode ignores the StereoMode flag and just
  splits the picture. Relabelling alone would fix flag-aware players and nothing
  else. Every filter graph verified against ffmpeg for all four layouts.
- New `mkvdiff --eyes`, which estimates eye order from horizontal disparity
  rather than leaving it to be judged by eye. Two parallel cameras give
  `x_left - x_right = f*b*(1/Z - 1/Zc)`: nearer than the screen is positive,
  further is negative. Films keep most of the frame at or behind the screen, so
  a correct pair measures negative and a swapped one positive. Verified against
  synthetic pairs of known geometry in both directions. Reported as evidence
  rather than proof, with the per-frame numbers shown.

## 3.30

- Encoder, 10-bit and Quality are separated by dividers rather than sitting in a
  run of similar-looking controls. Three unrelated settings on one row read as
  one setting otherwise.

## 3.29

- Encoder, 10-bit and quality now sit on one row. They are read together and
  changed together, and the wider panel made stacking them wasteful.
- Output folder and file name moved behind a Destination button beside Advanced
  Video Settings.
- New `tests/test_swift_structure.py`, run in CI. Nothing here can compile Swift
  and the app is edited far more often than it is built, so this checks the
  mistakes actually made in this repository: unbalanced brackets, a switch on
  the encoder that misses a case, a view using a computed property declared on a
  different view, and memberwise arguments passed out of declaration order.
  Each check was verified by introducing the fault and watching it fail. Two of
  them only worked after fixing substring matches that produced false negatives.

## 3.28

- **The FFmpeg staging file now goes to scratch, not to the destination.** It is
  a full-size encode, so writing it beside the output sent the entire encode
  across the network to a NAS and then read it back again for the remux. Only
  the finished file should ever land at the destination. It is also removed on
  exit, stop or crash, since a stray one silently costs tens of gigabytes.
- Advanced Video Settings sits on the same row as the section heading rather
  than floating above it.
- The window is now split one third drop zone, two thirds settings.

## 3.27

- **10-bit moved to the main panel, beside the encoder.** It changes the output
  profile, and being buried in Advanced meant finding out it was wrong after a
  three hour encode.
- **Fixed the Advanced sheet running off the screen.** It had no scroll view at
  all and a fixed 640pt width. The help sheet got that fix and this one did not,
  and the sheet has grown a lot since. Now scrolls, wraps and resizes.
- The 10-bit note no longer warns in orange for VideoToolbox. HEVC Main 10 is
  confirmed working on the target hardware; only x264 High 10 deserves a warning.

## 3.26

- **Reset to recommended, in Settings.** Saved defaults persist across upgrades,
  so the new settings in 3.23 never reached anyone who had used the app before.
  There was no way out of that short of deleting the plist by hand.
- **The app now notices when your saved defaults predate the current advice** and
  says so on the defaults panel, with "Use recommended" and "Keep mine". It does
  not overwrite anything: someone who chose x264 deliberately should keep it.
  Settings carry a schema number so this generalises to future changes.
- Settings names the plist, `~/Library/Preferences/local.mvc2sbs.app.plist`, for
  anyone who would rather do it from a terminal.
- `tests/test_settings_coverage.py` now ignores computed properties, which are
  not stored and cannot be decoded. It had started failing on one.

## 3.25

- Added `NEW-TOOL-BRIEF.md`, a design brief for a second tool that re-encodes
  existing H.264 files to HEVC. It carries the constraints this session
  established, so a fresh conversation starts from the conclusions rather than
  rediscovering them: mkvmerge for the mux, chapters without end times,
  `setparams` at the head of the filter chain, StereoMode preservation, the
  post-encode checks, and the measured settings.

## 3.24

- Fixed the timing table, which scaled extraction with film length. A MakeMKV MVC
  rip is bounded by the disc, not the runtime, so it is 30 to 45 GB either way
  and extraction takes about the same time regardless. A three hour film is
  around 55 minutes end to end rather than the hour previously stated.

## 3.23

- **App defaults are now the measured recommendation**: VideoToolbox, 10-bit,
  quality 62, dark tuning off. They were x264 at CRF 16 with dark tuning on,
  which was the original guess and produces a file roughly three times larger for
  no measurable gain. Existing saved settings are untouched.
- Replaced the "around 25 minutes for a feature" claim with a breakdown covering
  extraction, encoding and remuxing at two film lengths. The 25 minutes was the
  encode stage only, on a 91 minute film, and ignored the two stages either side
  of it.

## 3.22

- Corrected the caveat on the encoder comparison. The clip contains a camera
  move across high-contrast detail, so it tests more than grain and banding.

## 3.21

- Recommended settings are now `--vt --10bit --vt-quality 62`, confirmed
  indistinguishable from x265 CRF 20 by eye as well as by metric, at 27 times
  the speed. x265 kept as the alternative for a slightly smaller file.
- Noted what the comparison clip actually contains: grain and deep shadow, plus
  a slow pan across city lights on the night side of Earth. That is banding,
  grain retention and motion over fine high-contrast detail, which covers more
  than the previous note gave it credit for. Still not a fast-action test.

## 3.20

- **Fixed the help sheet not scrolling.** Its content had no width constraint, so
  long paragraphs laid out wider than the window instead of wrapping, the sheet
  scrolled sideways rather than down, and the right edge was cut off. It is also
  resizable now rather than fixed at 700x620.
- **VideoToolbox quality is settable in the app.** It never was: the app could
  select the encoder but not its only quality control, so every VideoToolbox
  encode ran at whatever the script defaulted to. Defaults to 62, the measured
  match for x265 CRF 20, with a button that sets it.
- The app no longer shows CRF and preset when VideoToolbox is selected. Neither
  does anything on that encoder, and offering settings that are silently ignored
  is worse than not offering them.
- The 10-bit note claimed you were producing H.264 High 10 when VideoToolbox was
  selected. It produces HEVC Main 10.
- Help sheet gained an encoder comparison with the measured figures, and the
  banding and CRF advice now matches what was measured rather than what the tool
  originally assumed.

## 3.19

- Replaced the interpolated VideoToolbox figure in the README with the measured
  one. Quality 62 gives 46.45 dB at 192 MB against x265 CRF 20's 46.16 dB at
  178 MB, in 15 seconds against 6 m 47 s. The interpolation had predicted
  165 MB and was 16% out.

## 3.18

- Documented a measured comparison of x265 against VideoToolbox on the same
  clip, against a common reference. VideoToolbox at quality 62 matches x265
  CRF 20 `slow` at slightly smaller size and roughly 25 times the speed, with
  the caveat that PSNR under-rates psychovisually tuned encoders.

## 3.17

- `mkvdiff` now narrates what it is doing, like `mvc2sbs` does. `--quality`
  reads every frame of both files, which on a 3840x1080 clip is a long silence
  that looks like a hang.
- `--quality` states plainly that it measures the difference between two files
  and not which of them is closer to the source. Two lossy encodes can sit 45 dB
  apart with either one the better. Ranking encoders needs a near-lossless
  reference, and the output now says so rather than leaving the number to be
  read as a verdict.

## 3.16

- `mkvdiff --quality` now prints both file sizes and which is smaller, and its
  verdict no longer says "take the smaller file" as though that were obvious
  from a PSNR number alone. Comparing x265 CRF 20 against VideoToolbox at
  quality 80 returned 45.9 dB, meaning equal quality, while the VideoToolbox
  file was 4.4 times larger. The number was right and the advice was useless.

## 3.15

- **Fixed the installer never copying the scripts.** This is the actual cause of
  every "it didn't install" report, and it was neither the folder nor `sort -V`.
  The decoder build does `cd "$SRCDIR"`, and the script's own directory was
  worked out *after* that from a relative `BASH_SOURCE`, so `dirname` gave `.`
  which by then was the edge264 source tree. Every copy step was guarded by
  `if [[ -f ... ]]`, so all three were skipped without a word and the script
  reported success. It now resolves its own directory as the first thing it
  does, and a missing source file is a hard error naming the directory it
  looked in.
- `tests/test_install.sh` gained three checks that would have caught it: the
  script's directory must be resolved before any `cd`, the installer must work
  when invoked by a relative path, and missing sources must fail loudly.

## 3.14

- The installer no longer uses `sort -V` to compare versions. BSD sort, which is
  what macOS ships, has not always supported it, and an unknown option exits 2
  and takes the whole script with it under `set -e`, before anything is copied.
  Replaced with a plain numeric comparison, tested across upgrade, downgrade and
  equal cases including 3.9 against 3.10 where a string compare gets it wrong.

## 3.13

- **Fixed the installer failing on a clean machine.** The downgrade guard added
  in 3.11 read the version of the already-installed copy; with `set -e` and
  pipefail, doing that when nothing is installed yet killed the script before it
  installed anything. It exited 2 after building the decoder and never copied
  the scripts across, so a fresh install silently left the old tools in place.
- **Fixed `--scripts-only` on a clean machine.** It skipped the section that
  creates the install directory, so there was nowhere to write.
- New `tests/test_install.sh`, run in CI, covering clean install, upgrade over
  an older copy, and the downgrade warning. Both bugs above were in code added
  to make installing safer, and neither was tested. The second was found by this
  test within a minute of writing it.

## 3.12

- `mvc2sbs --version`, matching `mkvdiff`. Checking which build you have should
  not require parsing help output.

## 3.11

- The installer refuses to quietly install an older build over a newer one, and
  names the folder it is installing from. macOS unpacks a second copy of an
  archive as "name 2" rather than replacing "name", so re-running the installer
  from a stale folder looks like it worked and changes nothing.
- `install-mac3d.sh --scripts-only` installs just the scripts, skipping Homebrew
  and the decoder build. That is the normal case after unpacking a release, and
  it takes a second rather than several minutes.
- The installer now prints the version of each tool it installed, and warns if a
  different copy sits earlier on your PATH and will run instead. A stale copy
  shadowing a new one has caused more confusion in this project than any actual
  bug.

## 3.10

- A second bare filename is now an error rather than silently replacing the
  first. Two commands pasted onto one line otherwise encodes the wrong file,
  which is an expensive way to find out.
- Documented cutting a test clip with `mkvmerge --split parts:` as the way to
  compare settings, rather than `--start` on the full source. Every encode then
  begins on the identical frame, which `--start` cannot guarantee because it
  snaps to a keyframe.

## 3.9

- **`--start` no longer decodes and discards everything before the start point.**
  It passed `-ss` to the encoder, whose video input is the decoder's pipe, and a
  pipe cannot seek, so FFmpeg satisfied it by reading and throwing away every
  frame from the beginning of the film. `--start 1590` decoded roughly 38,000
  frames before producing anything. The extraction seeks the source instead.
- **`--start` also produced desynchronised output.** The seek applied only to the
  video input, so the audio still began at the start of the film. Both inputs are
  now seeked together.
- Corrected the encode timing table. It carried a full-film figure extrapolated
  from a one minute clip of the opening, which is the cheapest minute in the
  film: the same settings run at 13 fps there and 2.5 fps at the 26 minute mark.

## 3.8

- Recommended settings are now `--x265 --10bit -q 20 -p slow`, about 7 GB a
  feature against the 29.5 GB the original x264 CRF 16 advice produced. Every
  part of it measured: codec compatibility on the target hardware, dither
  retention against bit depth, 52.5 dB PSNR between CRF 18 and 20 on real
  footage, and `--dark` making no visible difference at 10-bit.
- Replaced the encode timing table with measured figures. The old one carried
  numbers I never verified.

## 3.7

- `mkvdiff` reports a version, and an unrecognised option now says so instead of
  being treated as a filename. Running an older copy produced
  `FileNotFoundError: '--quality'`, which reads like a broken file rather than
  an out of date tool.
- `tests/test_version.py` now checks `mkvdiff` too.

## 3.6

- New `mkvdiff --quality A B`, which reports PSNR and SSIM between two encodes
  of the same footage. "I think this one is slightly clearer" is very hard to
  trust on dark material, and this settles it in about a minute. Refuses to
  compare files of different resolution or duration, because that still produces
  a number and the number is meaningless.
- The version number is now checked against this file by
  `tests/test_version.py`, which fails the build if `VERSION` in `mvc2sbs` does
  not match the topmost heading here. Three releases went out as 3.5 after I
  said every release would be bumped, which is what happens when a rule lives in
  someone's memory rather than in the tests.

## 3.5


- Confirmed on real footage that `--dark` is not worth using at 10-bit: one
  minute of Gravity's opening at x265 CRF 20, with and without, indistinguishable
  on a plasma, 62 MiB against 54 MiB.

- Every run now prints its version as the first line, and stamps the version and
  the settings used into the output file as Matroska tags. `mkvdiff` reports
  them as `mvc2sbs.version` and `mvc2sbs.settings`. Working out which build and
  which options produced a given file, from a folder full of them, was guesswork
  before, and guessing wrong sends you chasing faults that were fixed two
  versions ago. Several hours went that way yesterday.
- Versions are bumped on every release from here. Everything shipped yesterday
  went out labelled 3.4, which made the version number useless for the one job
  it has.

## 3.4

- **Changed x265's `--dark` tuning after measuring it.** It set
  `strong-intra-smoothing=0` on the strength of received wisdom about gradient
  banding; on a dithered dark ramp that retained less dither than leaving it
  alone. It now sets `sao=0`, which retained more dither than the default and
  produced a smaller file. Documented alongside the numbers that contradict the
  old claim.
- Measured `--dark` against bit depth: it is worth 5 to 8 points of dither
  retention at 8-bit and essentially nothing at 10-bit, where it costs 20 to 40%
  more bits for no measurable gain.

- **Fixed a colour round trip on every 10-bit encode.** The Y4M from the decoder
  carries no colour tags, and asking FFmpeg 8 for bt709 output is a conversion
  request rather than a labelling one. Converting transfer characteristics goes
  through linear light, so swscale routed every frame through 16-bit RGB
  ("No accelerated colorspace conversion found from yuv420p to bgr48le"). The
  filter chain now starts with `setparams`, which labels the frames so no
  conversion is needed. Confirmed on the affected machine. An earlier attempt to
  fix this with a `format` prefilter addressed the wrong thing and only appeared
  to work on the VideoToolbox path.
- The encoding line no longer claims a CRF and preset on VideoToolbox runs,
  which use neither.

- **Corrected the documented finding that no HEVC variant plays at 3840x1080 on
  an Nvidia Shield. All of them do.** Retested through the fixed pipeline: x265
  8-bit, x265 10-bit and VideoToolbox HEVC all direct play, with H.264 as a
  control. Every file in the original test was muxed by FFmpeg and carried
  FFmpeg chapters, both of which make that hardware refuse a file and both of
  which produce the same "black screen, no audio" symptom. The codec was never
  the variable.

- **The output is now muxed by MKVToolNix, not FFmpeg.** Both write a valid
  Matroska file with identical streams, and every field `mkvdiff` checks agrees
  between them, but Jellyfin's Android TV client on an Nvidia Shield refuses to
  direct play FFmpeg's and accepts MKVToolNix's. Measured by remuxing one file
  with `mkvmerge -o new.mkv old.mkv`, changing nothing else, and watching it
  start. FFmpeg now writes a staging file and mkvmerge produces the output. This
  rewrites the file once more at the end of an encode, which on a feature is a
  few minutes against a few hours. Without mkvtoolnix installed the FFmpeg file
  is kept and the reason is stated.
- The Cues check now tells the actual element apart from a SeekHead reference to
  it. mkvmerge writes Cues near the front of the file and FFmpeg writes them at
  the end, so the previous version reported every mkvmerge file as broken.

- **Fixed display dimensions, which made Jellyfin on an Nvidia Shield refuse to
  play the output at all.** A Full-SBS file now declares 3840x2160 rather than
  the per-eye 1920x1080 it declared before. Both are 16:9, so the aspect was
  never wrong; declaring a display smaller than the coded frame is what a server
  reads as "needs scaling" when deciding against direct play. Measured against a
  BD3D2MK3D file of the same disc that plays on the same hardware. Existing
  files can be fixed in place without re-encoding:
  `mkvpropedit FILE --edit track:v1 --set display-width=3840 --set display-height=2160`
- New `mkvdiff --gop`, which reports keyframe placement, picture types and frame
  sizes at the head of a file.

- New `--maxrate M`, a VBV cap in Mbps, and a Peak cap control in the app. CRF
  is a quality target with no rate ceiling, so peaks are unbounded. Measure with
  `mkvdiff --peak` before reaching for it.
- New `mkvdiff --luma`, which reports average picture brightness at a series of
  timestamps for one or two files. A black opening and a broken opening are
  identical in every container-level and bitrate measurement.
- New `mkvdiff --start`, which decodes the head of a file and reports where the
  first video packet, first audio packet and first keyframe are. Sound over a
  black picture that recovers on seeking is invisible to every container-level
  field, so none of the existing checks could see it.
- The Cues check reads the head and tail of the file rather than calling
  `mkvinfo -v`, which walks every cluster and so reads the whole file. On a
  feature film on a network share that took minutes. It now distinguishes an
  index that is present from one a truncated file merely references.
- **Chapters are carried across by MKVToolNix during that remux.** FFmpeg emits a
  `ChapterTimeEnd` on every chapter, which Matroska only defines for ordered
  editions. Players that read it as one build a broken virtual timeline: VLC
  showed no video window for the first 47 seconds of a feature, Kodi on a Shield
  needed a manual skip, and Jellyfin on the same Shield refused the file
  entirely. All three play once the element is gone. `mkvdiff` now reports
  `chapters_ordered_hint` so the fault is visible in one line.
- Every completed encode now decodes its own first three seconds and counts the
  frames, and checks that the file has a Cues index. A length check cannot see
  either of these faults, and both look the same to a viewer: sound plays and
  the picture stays black. An interrupted mux produces exactly this.
- Every completed encode is now checked for chapters that end past the end of
  the file. This is not cosmetic: a player that rejects them shows a black
  screen and plays no audio, which is indistinguishable from a broken encode.
  The check prints the fix, which rewrites a header rather than the file.
- New `--no-chapters`, and a Drop chapters toggle under Advanced Video Settings.
- Fixed saved settings being wiped by an upgrade. Swift's synthesised decoder
  throws on a missing key even when the property has a default value, so adding
  one setting silently reset every other one. `JobSettings` now decodes each key
  independently, and `tests/test_settings_coverage.py` fails the build if a new
  setting is added without being decoded or without being passed to the script.
- Help sheet gained a section on files that will not play.

## 3.3

- The app now detects a stale bundled `mvc2sbs`. `build-app.sh` stamps the app
  version from the script it bundles, and the app compares that against what
  `mvc2sbs --help` reports, warning if they differ. Previously a rebuild from an
  old folder produced an app that sent options its own bundled script had never
  heard of, and the error named the option rather than the mismatch.
- Settings shows both versions.

## 3.2

- Documented measured player compatibility: on a 2017 Shield via Jellyfin,
  3840x1080 H.264 plays and no variant of 3840x1080 HEVC does, at either bit
  depth and from either encoder.

- Fixed a colour round trip on the 10-bit VideoToolbox path. Some FFmpeg builds
  have no direct `yuv420p` to `p010le` conversion and route it through 16-bit
  RGB, which changed 74% of samples with a peak error of 95 in 1023. Converting
  via planar 10-bit first makes it a plain bit-depth increase.

## 3.1

- `--vt` now supports 10-bit via `p010le`, since the Apple Silicon media engine
  encodes 10-bit HEVC. Previously `--10bit` was ignored on that path.
- Added `--vt-quality`.
- Documented the measured encode rates: x265 at 3840x1080 preset slow runs at
  3 to 5 fps on an M1 Pro, which is 9 to 15 hours for a feature.

## 3.0

First public release. Everything below is the development history that led to it.

### Conversion
- Native MVC decode on Apple Silicon via edge264, no Windows VM required.
- Full and half side-by-side, full and half top-and-bottom layouts.
- x264, x265 and VideoToolbox encoders; CRF quality; 8-bit or 10-bit output.
- Audio, subtitles and chapters passed through without re-encoding.
- Per-track audio and subtitle selection.

### 3D subtitles
- PGS tracks rebuilt for the target layout by duplicating composition objects,
  so the bitmaps are never re-encoded.
- Adjustable disparity, brightness gamma, colour and opacity, all by rewriting
  palette segments only.

### Correctness fixes found during development
- `StereoMode` now sets the per-eye display dimensions alongside it. Without
  them a compliant reader derives a 2:1 sample aspect and stretches the picture
  to double width.
- `--limit` and `--start` no longer copy the film's chapters into an excerpt,
  where nearly all of them pointed past the end of the file. Some players reject
  such a file outright, playing neither video nor audio.
- Cancel now takes the whole pipeline down. Bash does not service traps while
  blocked on a foreground child, so long stages run in the background under
  `wait`, with a recursive kill and a bounded escalation to SIGKILL.
- The scratch stream is never written to a network volume, even when the output
  lives on one. The decoder memory-maps it and reads it continuously.
- Post-encode length verification against the source, because a dropped frame
  would silently desync the stream-copied audio.

### Verification tools
- `--info` scans the bitstream for MVC NAL units rather than trusting the
  Matroska codec ID, which is misleading on MakeMKV output.
- `--preview` decodes one frame and reports the PSNR between the two halves,
  with an interpretation, so "is this actually stereo" is a measurement.
- `--limit` for a 60 second smoke test.
- `mkvdiff` compares a file a player rejects against one it accepts.

### App
- SwiftUI front end with a batch queue, drag and drop, live progress and a log.
- Bundles `mvc2sbs`, `pgs3d.py` and the decoder, so it runs on a Mac that has
  never seen the install script. FFmpeg stays external, deliberately, to avoid
  redistributing a GPL build.
- `build-app.sh` fetches and builds the decoder if it is missing, and fails
  rather than shipping a bundle that cannot decode anything.
