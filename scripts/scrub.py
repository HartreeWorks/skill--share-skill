#!/usr/bin/env python3
"""Apply literal find->replace scrub rules to text files in a directory tree.

Rules file format (TSV): one rule per line, `find<TAB>replace`. `find` and
`replace` are treated as LITERAL strings (no regex, no escaping surprises).
Lines that are blank or start with `#` (after leading whitespace) are ignored.
A rule whose `find` is empty is skipped.

Usage: scrub.py <rules_file> <target_dir>

FAIL-CLOSED: a missing/unreadable rules file is a hard error (exit 2), never a
silent no-op — for a publish pipeline, skipping the scrub must never look like
success. Callers that treat a rules file as optional (e.g. a per-skill `.scrub`)
must gate the call with their own existence check.

The scrubber attempts to rewrite EVERY file, skipping only what is not valid
UTF-8 (i.e. true binary/asset files). It does not trust an extension allowlist:
rsync publishes every non-excluded file, so anything decodable as text must be
scanned or it could ship unscrubbed. A file that fails to decode AND is not a
recognised binary type is reported to stderr so a human can check it.
"""
import os
import sys

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", ".yarn", "dist", ".claude"}

# Extensions we expect to be binary; used ONLY to keep the "couldn't decode"
# warning quiet for genuine assets. It never gates scrubbing — decoding does.
BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp", ".tiff", ".svgz",
    ".pdf", ".zip", ".gz", ".tgz", ".tar", ".bz2", ".7z", ".rar",
    ".woff", ".woff2", ".ttf", ".otf", ".eot",
    ".mp3", ".mp4", ".mov", ".wav", ".m4a", ".aac", ".flac", ".webm", ".ogg",
    ".so", ".dylib", ".dll", ".bin", ".jar", ".class", ".pyc", ".pyo",
    ".wasm", ".node", ".sqlite", ".db",
}


def load_rules(path):
    rules = []
    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")  # tolerate CRLF-saved rules files
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "\t" not in line:
                print(f"  scrub: skipping malformed rule (no tab) at "
                      f"{os.path.basename(path)}:{lineno}", file=sys.stderr)
                continue
            find, replace = line.split("\t", 1)
            if find == "":
                continue
            rules.append((find, replace))
    return rules


def main():
    if len(sys.argv) != 3:
        print("Usage: scrub.py <rules_file> <target_dir>", file=sys.stderr)
        sys.exit(2)
    rules_file, target = sys.argv[1], sys.argv[2]

    if not os.path.isfile(rules_file):
        # Fail closed: never silently skip a scrub the caller asked for.
        print(f"  scrub: ERROR — rules file not found: {rules_file}", file=sys.stderr)
        sys.exit(2)
    rules = load_rules(rules_file)
    if not rules:
        print(f"  scrub: {os.path.basename(rules_file)} has no active rules; nothing to do")
        return

    changed = 0
    skipped_unreadable = []
    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            fp = os.path.join(root, name)
            try:
                with open(fp, encoding="utf-8") as fh:
                    content = fh.read()
            except UnicodeDecodeError:
                # Not UTF-8 text. Silent for known binary assets; flagged
                # otherwise so a human can confirm it holds nothing private.
                if os.path.splitext(name)[1].lower() not in BINARY_EXTS:
                    skipped_unreadable.append(os.path.relpath(fp, target))
                continue
            except OSError:
                skipped_unreadable.append(os.path.relpath(fp, target))
                continue
            new = content
            for find, replace in rules:
                if find in new:
                    new = new.replace(find, replace)
            if new != content:
                with open(fp, "w", encoding="utf-8") as fh:
                    fh.write(new)
                changed += 1

    print(f"  scrub: applied {len(rules)} rule(s) from "
          f"{os.path.basename(rules_file)} ({changed} file(s) changed)")
    if skipped_unreadable:
        print("  scrub: WARNING — these files are not valid UTF-8 and were NOT "
              "scrubbed; verify they contain no private info:", file=sys.stderr)
        for rel in skipped_unreadable:
            print(f"    - {rel}", file=sys.stderr)


if __name__ == "__main__":
    main()
