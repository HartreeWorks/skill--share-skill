#!/bin/bash
# Publish a local skill to its public GitHub repo.
# Syncs all files except data/ and private files, then commits and pushes.
#
# Usage: publish-skill.sh <skill-name-or-path> [commit-message] [--release "user-facing note"]
# Examples:
#   publish-skill.sh summarise-call "Add new template support"           # global skill
#   publish-skill.sh ~/Documents/Projects/foo/.claude/skills/bar "Fix typo" # project-local skill
#   publish-skill.sh find-hotel "Add noise screen" --release "Screens recent reviews for noise"
#
# --release bumps the skill's VERSION (YYYY.MM.DD.N) and adds the note to its
# CHANGES.md, both in the private source (commit them afterwards), then tags the
# public commit v<VERSION>. Installed copies offer the user each new release.
# Skills with a VERSION file also get the update scripts from the add-auto-update skill
# injected into the published copy on every publish.
#
# The first argument may be either a bare skill name (resolved against
# ~/.agents/skills/) or a path to a skill directory anywhere on disk.
set -euo pipefail

SKILL_ARG="${1:?Usage: publish-skill.sh <skill-name-or-path>}"
shift
COMMIT_MSG=""
RELEASE_NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE_NOTE="${2:?--release needs a user-facing note}"; shift 2 ;;
    *) COMMIT_MSG="$1"; shift ;;
  esac
done

# Directory of this script (so we can find the scrub rules and helper scripts).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_RULES="$SCRIPT_DIR/../scrub-rules.tsv"

# Fail closed: the global scrub is the primary privacy defence. If its rules
# file is missing we must NOT proceed to publish an unscrubbed copy.
if [ ! -f "$GLOBAL_RULES" ]; then
  echo "Error: global scrub rules not found: $GLOBAL_RULES" >&2
  echo "Refusing to publish without the global scrub — aborting." >&2
  exit 1
fi

# The rsync filters keep secrets and .git out of the copy; never publish without them.
PUBLISH_FILTERS="$SCRIPT_DIR/publish-filters.rules"
if [ ! -f "$PUBLISH_FILTERS" ]; then
  echo "Error: publish filters not found: $PUBLISH_FILTERS — aborting." >&2
  exit 1
fi

# Resolve the skill directory: treat the argument as a path if it points at an
# existing directory, otherwise fall back to the global skills location.
if [ -d "$SKILL_ARG" ]; then
  SKILL_DIR="$(cd "$SKILL_ARG" && pwd)"
else
  SKILL_DIR="$HOME/.agents/skills/$SKILL_ARG"
fi

# The skill name (and therefore the public repo name) is always the folder name.
SKILL_NAME="$(basename "$SKILL_DIR")"
REPO_NAME="skill--$SKILL_NAME"
REPO_FULL="HartreeWorks/$REPO_NAME"
TEMP_DIR=""

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    if command -v trash >/dev/null 2>&1; then
      trash "$TEMP_DIR"
    else
      echo "Warning: trash command not found; leaving temp dir in place: $TEMP_DIR" >&2
    fi
  fi
}
trap cleanup EXIT

# Validate skill exists
if [ ! -d "$SKILL_DIR" ]; then
  echo "Error: Skill directory not found: $SKILL_DIR" >&2
  exit 1
fi

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "Error: No SKILL.md found in $SKILL_DIR" >&2
  exit 1
fi

# Check public repo exists (handle the lesswrong naming exception)
if ! gh repo view "$REPO_FULL" --json name >/dev/null 2>&1; then
  # Try alternative naming convention
  ALT_REPO="HartreeWorks/claude-skill--$SKILL_NAME"
  if gh repo view "$ALT_REPO" --json name >/dev/null 2>&1; then
    REPO_FULL="$ALT_REPO"
    REPO_NAME="claude-skill--$SKILL_NAME"
  else
    echo "Error: Public repo not found: $REPO_FULL" >&2
    echo "Create it first with: gh repo create $REPO_FULL --public" >&2
    exit 1
  fi
fi

echo "Publishing $SKILL_NAME → $REPO_FULL"

# Shallow clone the public repo
TEMP_DIR="$(mktemp -d)"
echo "Cloning $REPO_FULL to temp dir..."
git clone --depth 1 "https://github.com/$REPO_FULL.git" "$TEMP_DIR/repo" 2>&1 | sed 's/^/  /'

# Rsync local → public, excluding private files. The rules live in
# publish-filters.rules (shared with changed-files.py); they honour the skill's
# .gitignore files and drop data/, secrets, caches and build output.
echo "Syncing files..."
rsync -av --delete \
  --filter="merge $PUBLISH_FILTERS" \
  "$SKILL_DIR/" "$TEMP_DIR/repo/" 2>&1 | sed 's/^/  /'

# Scrub private info from the published copy. Two passes, deterministic and
# repeatable so small refinements to an already-shared skill re-publish without
# redoing the manual anonymisation:
#   1. Global rules (scrub-rules.tsv): Peter's unambiguous personal identifiers
#      (paths, emails, phones, calendar IDs) — applied to every skill.
#   2. Per-skill .scrub (optional): this skill's context-specific replacements
#      (client/project names, sample data, location refs) remembered from the
#      first review, so they never have to be re-derived.
# The model's review only needs to look for NOVEL leaks not covered by these.

# The update scripts come from the add-auto-update skill, kept outside the
# folders agents scan for skills, or installed alongside this one.
AUTO_UPDATE="$HOME/.agents/skills-unlisted/add-auto-update"
[ -d "$AUTO_UPDATE" ] || AUTO_UPDATE="$SCRIPT_DIR/../../add-auto-update"

# Release: bump VERSION and record the note in the private source, then copy
# both into the published copy (rsync ran before they changed).
VERSION=""
if [ -n "$RELEASE_NOTE" ]; then
  VERSION="$(bash "$AUTO_UPDATE/scripts/release.sh" "$SKILL_DIR" "$RELEASE_NOTE" 2>/dev/null)"
  cp "$SKILL_DIR/VERSION" "$SKILL_DIR/CHANGES.md" "$TEMP_DIR/repo/"
  echo "Release $VERSION: $RELEASE_NOTE"
fi

# Versioned skills get the shared update scripts (check-update, migrate, data-dir).
if [ -f "$SKILL_DIR/VERSION" ]; then
  bash "$AUTO_UPDATE/scripts/install.sh" "$TEMP_DIR/repo" --repo "$REPO_FULL" --name "$SKILL_NAME" \
    --data-root hartreeworks-skills
fi

echo "Scrubbing (global rules)..."
python3 "$SCRIPT_DIR/scrub.py" "$GLOBAL_RULES" "$TEMP_DIR/repo"
if [ -f "$SKILL_DIR/.scrub" ]; then
  echo "Scrubbing (per-skill .scrub)..."
  python3 "$SCRIPT_DIR/scrub.py" "$SKILL_DIR/.scrub" "$TEMP_DIR/repo"
fi

# Ensure data/ is in the public repo's .gitignore
GITIGNORE="$TEMP_DIR/repo/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qx 'data/' "$GITIGNORE"; then
    echo "" >> "$GITIGNORE"
    echo "# Private local data (not published)" >> "$GITIGNORE"
    echo "data/" >> "$GITIGNORE"
  fi
else
  cat > "$GITIGNORE" <<'GITIGNORE_EOF'
# Private local data (not published)
data/

# OS files
.DS_Store

# Python
__pycache__/
*.pyc

# Node
node_modules/
GITIGNORE_EOF
fi

# Commit and push
cd "$TEMP_DIR/repo"
git add -A

if git diff --cached --quiet; then
  echo "No changes to publish."
  # Source still matches what's published — refresh the manifest so the next
  # re-publish can scope its review correctly.
  python3 "$SCRIPT_DIR/changed-files.py" --write "$SKILL_DIR" "$SKILL_DIR/.publish-state.json" || \
    echo "  (warning: could not write .publish-state.json manifest)" >&2
  exit 0
fi

echo ""
echo "Changes to publish:"
git diff --cached --stat

if [[ -z "$COMMIT_MSG" ]]; then
  # `|| true` so a grep that matches nothing (e.g. only .gitignore staged)
  # doesn't trip `set -o pipefail` and abort the publish. Dot escaped so it
  # doesn't strip unrelated paths merely containing "gitignore".
  CHANGED_FILES=$(git diff --cached --name-only | { grep -v '\.gitignore' || true; } | head -5 | tr '\n' ', ' | sed 's/,$//')
  COMMIT_MSG="Update $SKILL_NAME: $CHANGED_FILES"
fi

echo ""
git commit -m "$COMMIT_MSG"
# Push a release tag before the branch: installed copies read VERSION from the
# branch and install the matching tag, which must already exist.
if [ -n "$VERSION" ]; then
  git tag "v$VERSION"
  git push origin "v$VERSION"
  echo "Tagged v$VERSION. Commit VERSION and CHANGES.md in the source."
fi
git push origin HEAD

# Record what was published so the next re-publish can scope its privacy review
# to only the files that changed (see changed-files.py). Written into the source
# skill dir and excluded from the published copy. Never fatal to the publish.
python3 "$SCRIPT_DIR/changed-files.py" --write "$SKILL_DIR" "$SKILL_DIR/.publish-state.json" || \
  echo "  (warning: could not write .publish-state.json manifest)" >&2

echo ""
echo "Published $SKILL_NAME to https://github.com/$REPO_FULL"
