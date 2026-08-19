#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The rules that decide what happens to a file, exercised without any media.

mkvshrink's pipeline needs real video and cannot be tested here. Its decisions
can: which audio and subtitle tracks are kept, and which are dropped, is pure
logic over the JSON that mkvmerge and ffprobe produce. That is also the part
where being wrong is expensive and silent. Dropping the Japanese track of a
Japanese film is not a crash, it is a film you cannot watch in its own language,
discovered weeks later.

The probe stage is extracted from the script and run directly against synthetic
JSON. It is the same text the script runs, read out of the script itself, so it
cannot drift from what ships.

The cases are the ones the documentation makes promises about, plus the hole it
admits to, which is asserted as it actually behaves rather than as anyone would
like it to behave.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = (ROOT / "mkvshrink").read_text()

failures = []


def check(ok, msg):
    print(("  ok   " if ok else "  FAIL ") + msg)
    if not ok:
        failures.append(msg)


# The probe stage, lifted out of the heredoc it lives in.
m = re.search(r"read -r -d '' PROBE_PY <<'PROBEPY' \|\| true\n(.*?)\nPROBEPY",
              SCRIPT, re.S)
if not m:
    print("FAIL cannot find PROBE_PY in mkvshrink")
    sys.exit(1)
PROBE_PY = m.group(1)


def track(tid, ttype, codec, lang, name="", default=False, forced=False,
          hi=False, commentary=False):
    return {
        "id": tid,
        "type": ttype,
        "codec": codec,
        "properties": {
            "language": lang,
            "track_name": name,
            "default_track": default,
            "forced_track": forced,
            "flag_hearing_impaired": hi,
            "flag_commentary": commentary,
        },
    }


def run(tracks, sub_langs="eng,en,und", aud_langs="eng,en",
        keep_comm="1", keep_forced="1", keep_all="0"):
    """The probe stage's own output, as the script would eval it."""
    with tempfile.TemporaryDirectory() as tmp:
        mkv = os.path.join(tmp, "mkv.json")
        ff = os.path.join(tmp, "ff.json")
        table = os.path.join(tmp, "table.txt")
        tsv = os.path.join(tmp, "table.tsv")
        json.dump({"tracks": tracks,
                   "container": {"properties": {"duration": 3600000000000}}},
                  open(mkv, "w"))
        json.dump({"streams": [], "format": {"duration": "3600.0",
                                             "size": "10000000000"}},
                  open(ff, "w"))
        r = subprocess.run(
            [sys.executable, "-c", PROBE_PY, mkv, ff, table,
             sub_langs, aud_langs, keep_comm, keep_forced, keep_all, tsv],
            capture_output=True, text=True)
        out = {}
        for line in r.stdout.splitlines():
            if "=" in line:
                k, _, v = line.partition("=")
                out[k] = shlex.split(v)[0] if v else ""
        out["_table"] = open(table).read() if os.path.exists(table) else ""
        out["_tsv"] = open(tsv).read() if os.path.exists(tsv) else ""
        out["_stderr"] = r.stderr
        return out


VIDEO = track(0, "video", "AVC/H.264/MPEG-4p10", "und")


def ids(value):
    return [x for x in value.replace(",", " ").split() if x]


print("subtitle rules")

# English, undetermined, and a forced track in any language.
r = run([VIDEO,
         track(1, "audio", "DTS", "eng"),
         track(2, "subtitles", "PGS", "eng"),
         track(3, "subtitles", "PGS", "fre"),
         track(4, "subtitles", "PGS", "fre", forced=True),
         track(5, "subtitles", "PGS", "und")])
keep = ids(r.get("SUBS_KEEP", ""))
check("2" in keep, "keeps an English subtitle track")
check("5" in keep, "keeps an undetermined one")
check("3" not in keep, "drops a French one")
check("4" in keep, "keeps a FORCED French one, which carries dialogue")

# --no-forced has to actually drop it. There has to be a second subtitle track
# that IS kept, or the empty-selection fallback keeps everything and the test
# passes for the wrong reason.
r = run([VIDEO, track(1, "audio", "DTS", "eng"),
         track(2, "subtitles", "PGS", "eng"),
         track(3, "subtitles", "PGS", "fre", forced=True)],
        keep_forced="0")
keep = ids(r.get("SUBS_KEEP", ""))
check("3" not in keep and "2" in keep, "--no-forced drops the forced track")

# SDH by name, on a track whose language would have kept it anyway: the point
# is that the flag is reported, since the table is what a plan review reads.
r = run([VIDEO, track(1, "audio", "DTS", "eng"),
         track(2, "subtitles", "PGS", "eng", name="English SDH")])
check("sdh" in r["_table"], "an SDH track is labelled as one in the table")

print("audio rules")

# The documented rule: whitelist, plus the first track whatever it is.
r = run([VIDEO,
         track(1, "audio", "DTS", "jpn"),
         track(2, "audio", "AC3", "eng"),
         track(3, "audio", "AC3", "spa")])
keep = ids(r.get("AUDIO_KEEP", ""))
check("1" in keep, "keeps track 1 whatever its language")
check("2" in keep, "keeps English")
check("3" not in keep, "drops Spanish")

# The hole the README admits to. Asserted as it behaves, not as anyone wants.
# If this ever starts passing, the rule improved and the docs need updating.
r = run([VIDEO,
         track(1, "audio", "AC3", "eng", name="English dub"),
         track(2, "audio", "AC3", "eng"),
         track(3, "audio", "AC3", "eng"),
         track(4, "audio", "DTS", "jpn")])
keep = ids(r.get("AUDIO_KEEP", ""))
check("4" not in keep,
      "the known hole is still the known hole: an original-language track "
      "that is neither first nor whitelisted is dropped")
check("jpn" in r.get("AUDIO_LOST_LANGS", ""),
      "and the loss is named, so a plan review can catch it")

# Losing every subtitle track is a film with no subtitles at all, so the rules
# give up and keep them rather than deliver that.
r = run([VIDEO, track(1, "audio", "DTS", "eng"),
         track(2, "subtitles", "PGS", "fre"),
         track(3, "subtitles", "PGS", "spa")],
        sub_langs="jpn", keep_forced="0")
check(ids(r.get("SUBS_KEEP", "")) == ["2", "3"],
      "an empty subtitle selection falls back to keeping everything")
check("subtitle" in r.get("WARNINGS", "").lower(),
      "and says so rather than doing it silently")

# The matching audio fallback exists but cannot fire, because the rule above it
# keeps the first audio track whatever its language, so the selection is never
# empty while there is any audio at all. Asserting that here means the day
# somebody removes the first-track rule, this says the guard now matters.
r = run([VIDEO, track(1, "audio", "DTS", "jpn"), track(2, "audio", "AC3", "spa")],
        aud_langs="fre")
check(ids(r.get("AUDIO_KEEP", "")) == ["1"] and not r.get("WARNINGS", ""),
      "the first-track rule means the audio fallback never has to fire")

print("keep everything")

r = run([VIDEO,
         track(1, "audio", "DTS", "jpn"),
         track(2, "audio", "AC3", "spa"),
         track(3, "subtitles", "PGS", "fre")],
        keep_all="1")
check(len(ids(r.get("AUDIO_KEEP", ""))) == 2 and len(ids(r.get("SUBS_KEEP", ""))) == 1,
      "--keep-all-tracks drops nothing")

print("the machine readable track table")

# What the GUI reads to offer "keep this one after all". The human table is
# space aligned and track names contain spaces, so it cannot be parsed back.
r = run([VIDEO,
         track(1, "audio", "AC3", "eng", name="English Dub"),
         track(2, "audio", "FLAC", "jpn", name="Original Japanese"),
         track(3, "subtitles", "PGS", "eng")])
lines = [l for l in r["_tsv"].splitlines() if l]
head = lines[0].lstrip("#").split("\t")
check(head == ["id", "type", "lang", "codec", "channels", "flags", "bytes",
               "keep", "why", "name"],
      "the track TSV header is the one TrackInfo.parse expects")
rows = {l.split("\t")[0]: l.split("\t") for l in lines[1:]}
check(len(rows) == 4, "every track is listed, video included")
check(rows["2"][2] == "jpn" and rows["2"][7] == "0",
      "the Japanese track is listed as one the rules drop")
check(rows["2"][9] == "Original Japanese",
      "its name comes through, which is how you recognise it")
check(rows["1"][7] == "1" and rows["1"][8] == "first",
      "the English dub is kept, and says it was kept for being first")
check("\t" not in rows["2"][9], "no field can contain a tab")

print("planning leaves no trace")

# A plan changes nothing on disk. It used to write its probe clips into the
# folder the film was in, which does not change the film but does restamp the
# directory: a library created in 2015 came back modified today, from a run
# that was only reading.
m = re.search(r'if \[\[ "\$D_ACTION" == "shrink" \]\]; then\n(.*?)\n', SCRIPT)
check(bool(m) and "probe_scratch" in m.group(1),
      "the planner cuts its probe clips in scratch, not beside the source")
check("mkvshrink-probe" in SCRIPT and re.search(r"trap .*mkvshrink-probe", SCRIPT),
      "and removes that scratch directory when it exits")

print("files it must refuse")

r = run([track(0, "audio", "DTS", "eng")])
check(r.get("OK") == "0" and "no video" in r.get("ERR", ""),
      "a file with no video track is refused, with a reason")

print("\nprobe stage lines: %d" % len(PROBE_PY.splitlines()))

if failures:
    print("\n%d check(s) failed" % len(failures))
    sys.exit(1)
print("\nall checks passed")
