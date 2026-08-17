#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""Structural checks on the SwiftUI source.

Nothing in this repository's CI can compile Swift, and the app is edited far
more often than it is built. These are the mistakes that have actually been made
here, each of which would otherwise surface as a compiler error on the user's
machine after a download:

- unbalanced braces, parens or brackets from a bad edit
- a `switch` on EncoderKind that does not cover every case
- a view referencing a computed property that lives on a different view
- a view constructed with an argument it does not declare
- memberwise initialiser arguments passed out of declaration order, which Swift
  rejects outright

It is a lint, not a compiler. It cannot prove the file builds.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "app/Sources"

failures = []


def strip_literals(s):
    """Remove string literals and line comments so brace counting is honest."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def top_level_labels(args):
    """Argument labels at depth 0 only.

    `queue.outputURL(for: job)` as an argument value must not contribute `for`.
    """
    labels, depth, i = [], 0, 0
    while i < len(args):
        c = args[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0:
            m = re.match(r"(\w+)\s*:", args[i:])
            if m and (i == 0 or args[i - 1] in "(, \n\t"):
                labels.append(m.group(1))
                i += m.end()
                continue
        i += 1
    return labels


def split_args(text):
    """The argument list of a call, respecting nesting."""
    depth, out, start = 0, [], 0
    for i, c in enumerate(text):
        if c in "([":
            depth += 1
        elif c in ")]":
            if depth == 0:
                out.append(text[start:i])
                return "".join(out)
            depth -= 1
    return text


for path in sorted(SRC_DIR.glob("*.swift")):
    src = path.read_text()
    code = strip_literals(src)
    name = path.name

    for opener, closer in (("{", "}"), ("(", ")"), ("[", "]")):
        if code.count(opener) != code.count(closer):
            failures.append(
                "%s: unbalanced %s%s, %d against %d"
                % (name, opener, closer, code.count(opener), code.count(closer))
            )

    # Swift accepts only \0 \\ \t \n \r \" \' and \u{...} in a string literal.
    # Anything else is a compile error, and these strings are long and written by
    # hand.
    # \( is string interpolation, which is everywhere in SwiftUI.
    VALID = set("0\\tnr\"'u(")
    i, n = 0, len(src)
    while i < n:
        if src[i] == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    if i + 1 < n and src[i + 1] not in VALID:
                        line = src[:i].count("\n") + 1
                        failures.append(
                            "%s:%d invalid escape \\%s in a string literal"
                            % (name, line, src[i + 1])
                        )
                    i += 2
                    continue
                i += 1
        i += 1

    # A switch over the encoder must handle every case or carry a default.
    for blk in re.findall(r"switch\s+\S*encoder\s*\{(.*?)\n        \}", src, re.S):
        cases = set(re.findall(r"case \.(\w+)", blk))
        if "default" not in blk and cases != {"x264", "x265", "videotoolbox"}:
            failures.append("%s: switch on encoder covers only %s" % (name, sorted(cases)))

    # Computed properties are scoped to their own view. These names are never
    # argument labels, so a match outside the declaring struct is a real error.
    for chunk in re.split(r"\nstruct ", src)[1:]:
        struct = chunk.split()[0].rstrip(":")
        for prop in ("tenBitNote", "vtNote", "crfNote", "nameFocused"):
            # Word boundaries, not substrings: "var vtNoteRenamed" contains
            # "var vtNote" and would look like a declaration that is not there.
            used = re.search(r"\b%s\b" % prop, chunk)
            declared_here = re.search(r"\bvar %s\b" % prop, chunk)
            if used and not declared_here:
                failures.append("%s: %s uses %s but does not declare it" % (name, struct, prop))

    # Views must be constructed with parameters they declare, in declaration
    # order. Swift requires memberwise arguments in order and errors if not.
    for struct_name in re.findall(r"struct (\w+): View \{", src):
        decl_match = re.search(
            r"struct %s: View \{(.*?)\n    var body" % struct_name, src, re.S
        )
        if not decl_match:
            continue
        decl = decl_match.group(1)
        order = re.findall(
            r"^    (?:@\w+(?:\([^)]*\))? )?(?:var|let) (\w+)", decl, re.M
        )
        declared = set(order)
        for call in re.finditer(r"\b%s\(" % struct_name, src):
            args = split_args(src[call.end():])
            labels = top_level_labels(args)
            unknown = [l for l in labels if l not in declared]
            if unknown:
                failures.append(
                    "%s: %s constructed with unknown parameter(s) %s"
                    % (name, struct_name, ", ".join(unknown))
                )
                continue
            positions = [order.index(l) for l in labels]
            if positions != sorted(positions):
                failures.append(
                    "%s: %s arguments out of declaration order: %s, declared %s"
                    % (name, struct_name, labels, order)
                )

    # NSCursor.push() and pop() have to balance or the resize cursor leaks out
    # over the rest of the window and stays there.
    pushes = len(re.findall(r"NSCursor\.\w+\.push\(\)", src))
    pops = len(re.findall(r"NSCursor\.pop\(\)", src))
    if pushes != pops:
        failures.append("%s: %d NSCursor push against %d pop" % (name, pushes, pops))


print("checked %d Swift files" % len(list(SRC_DIR.glob("*.swift"))))
if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("ok")
