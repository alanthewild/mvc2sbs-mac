# Third party notices

MVC2SBS is MIT licensed. It bundles one third party component and depends on
several others at runtime. This file records what they are, how they are used
and what their licences require.

## Bundled into the application

### edge264 (MVC fork)

`edge264_test` is compiled from source and copied into
`MVC2SBS.app/Contents/Resources/`. It is the H.264/MVC decoder, and it is the
one piece that makes this project possible at all: it is the only open source
decoder that reads the dependent view of a 3D Blu-ray on Apple Silicon.

- Upstream: https://github.com/tvlabs/edge264
- MVC fork used here: https://github.com/cbusillo/edge264-mvc
- Licence: BSD 3-Clause

Because a built `.app` redistributes this binary, the BSD licence requires its
copyright notice to travel with it. That notice is reproduced in full below.

```
Copyright (c) 2013-2014, Celticom / TVLabs
Copyright (c) 2014-2026 Thibault Raffaillac <traf@kth.se>
Copyright (c) 2026 Jens Duttke
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Required at runtime, not bundled

### FFmpeg

Used for demuxing, encoding and muxing. Installed separately with
`brew install ffmpeg`.

- https://ffmpeg.org
- Licence: LGPL 2.1 or later, and GPL 2 or later when built with x264, which
  the Homebrew build is.

MVC2SBS invokes the `ffmpeg` and `ffprobe` executables as separate processes.
It does not link against any FFmpeg library, so no FFmpeg licence obligation
attaches to this project's own code.

**FFmpeg is deliberately not bundled.** Beyond the practical problem of
relocating its dylibs, redistributing a GPL FFmpeg build inside an application
brings the GPL's source distribution obligations with it. Leaving users to
install it themselves avoids that entirely.

### MKVToolNix

`mkvpropedit` sets the Matroska StereoMode flag and the per-eye display
dimensions. Optional: without it the output plays, but carries no 3D flag.
Installed with `brew install mkvtoolnix`.

- https://mkvtoolnix.download
- Licence: GPL 2

Invoked as a separate process, same reasoning as FFmpeg.

### x264 and x265

Used through FFmpeg rather than directly.

- https://www.videolan.org/developers/x264.html
- https://www.x265.org
- Licence: GPL 2 or later, both

## Not used, but owed credit

### MakeMKV

Produces the 3D MVC MKV files this tool consumes. Proprietary, not bundled, not
invoked. https://www.makemkv.com

### BD3D2MK3D

The Windows tool this project replaces on macOS, by r0lZ. Freeware rather than
open source. No code was taken from it; it defined what the output should look
like, and its defaults are the reason CRF 16 and Full-SBS are the defaults here.
https://www.videohelp.com/software/BD3D2MK3D

### Matroska specification

The StereoMode and display dimension behaviour is implemented from RFC 9559 and
the Matroska specification notes.

- https://www.rfc-editor.org/rfc/rfc9559.html
- https://www.matroska.org/technical/notes.html
