#!/usr/bin/env python3
"""Track which source files changed since a skill was last published.

The security & privacy review is the slow part of re-publishing a skill. Most
of it is redundant when only a couple of files changed since last time. This
script scopes that review: it hashes every publishable file in a skill dir and
compares against a manifest written at the last publish
(`<skill_dir>/.publish-state.json`).

Two modes:

  changed-files.py <skill_dir>
      Compare against the manifest and print NEW / CHANGED / UNCHANGED files.
      The review step only needs a fresh manual privacy scan of NEW + CHANGED
      files; UNCHANGED files are covered by the last review plus the
      deterministic scrub rules. With no manifest, every file is NEW (full
      review) — the safe default.

  changed-files.py --write <skill_dir> <manifest_path>
      Recompute hashes and write the manifest. Called by publish-skill.sh after
      a successful push.

Hashing errs toward "review it": anything not in the manifest counts as NEW, so
a stale or missing manifest can never cause a changed file to be skipped.
"""
import hashlib
import json
import os
import sys
from datetime import datetime

# Kept in rough sync with publish-skill.sh's rsync excludes. Perfect fidelity is
# not required: the manifest scopes a human/model review, it is not a security
# boundary. Mis-tracking at worst reviews an extra file (safe).
SKIP_DIRS = {".git", "data", "node_modules", "__pycache__", ".venv", ".yarn",
             "dist", ".claude"}
SKIP_FILES = {".DS_Store", "config.json", ".scrub", ".publish-state.json"}


def is_skipped_file(name):
    if name in SKIP_FILES:
        return True
    if name.startswith(".env"):
        return True
    if name.endswith(".pyc"):
        return True
    if ".sync-conflict-" in name:
        return True
    return False


def hash_files(skill_dir):
    """Return {relpath: sha256} for every publishable file under skill_dir."""
    out = {}
    for root, dirs, files in os.walk(skill_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if is_skipped_file(name):
                continue
            fp = os.path.join(root, name)
            rel = os.path.relpath(fp, skill_dir)
            try:
                with open(fp, "rb") as fh:
                    out[rel] = hashlib.sha256(fh.read()).hexdigest()
            except OSError:
                continue
    return out


def write_manifest(skill_dir, manifest_path):
    manifest = {
        "published_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "files": hash_files(skill_dir),
    }
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"  manifest: recorded {len(manifest['files'])} file(s) → "
          f"{os.path.basename(manifest_path)}")


def compare(skill_dir):
    manifest_path = os.path.join(skill_dir, ".publish-state.json")
    current = hash_files(skill_dir)
    if not os.path.isfile(manifest_path):
        print("No .publish-state.json — treat every file as NEW (full review):")
        for rel in sorted(current):
            print(f"  NEW       {rel}")
        return
    with open(manifest_path, encoding="utf-8") as fh:
        prev = json.load(fh).get("files", {})

    new, changed, unchanged = [], [], []
    for rel, digest in sorted(current.items()):
        if rel not in prev:
            new.append(rel)
        elif prev[rel] != digest:
            changed.append(rel)
        else:
            unchanged.append(rel)
    removed = sorted(set(prev) - set(current))

    for rel in new:
        print(f"  NEW       {rel}")
    for rel in changed:
        print(f"  CHANGED   {rel}")
    for rel in removed:
        print(f"  REMOVED   {rel}")
    for rel in unchanged:
        print(f"  unchanged {rel}")

    to_review = len(new) + len(changed)
    print()
    if to_review == 0 and not removed:
        print("Nothing changed since last publish — no new privacy review needed.")
    else:
        print(f"Review scope: {len(new)} new + {len(changed)} changed file(s) "
              f"need a fresh privacy scan; {len(unchanged)} unchanged.")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--write":
        if len(args) != 3:
            print("Usage: changed-files.py --write <skill_dir> <manifest_path>",
                  file=sys.stderr)
            sys.exit(2)
        write_manifest(args[1], args[2])
        return
    if len(args) != 1:
        print("Usage: changed-files.py <skill_dir>  |  "
              "changed-files.py --write <skill_dir> <manifest_path>",
              file=sys.stderr)
        sys.exit(2)
    compare(args[0])


if __name__ == "__main__":
    main()
