#!/bin/bash
# Publish a local skill to its public GitHub repo.
# Syncs all files except data/ and private files, then commits and pushes.
#
# Usage: publish-skill.sh <skill-name-or-path> [commit-message]
# Examples:
#   publish-skill.sh summarise-granola "Add new template support"           # global skill
#   publish-skill.sh ~/Documents/Projects/foo/.claude/skills/bar "Fix typo" # project-local skill
#
# The first argument may be either a bare skill name (resolved against
# ~/.agents/skills/) or a path to a skill directory anywhere on disk.
set -euo pipefail

SKILL_ARG="${1:?Usage: publish-skill.sh <skill-name-or-path>}"

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

# Rsync local → public, excluding private files.
# --filter=':- .gitignore' honours the skill's .gitignore (e.g. transcripts/).
echo "Syncing files..."
rsync -av --delete \
  --filter=':- .gitignore' \
  --exclude='data/' \
  --exclude='.DS_Store' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='*.env' \
  --exclude='config.json' \
  --exclude='*.pem' \
  --exclude='*.key' \
  --exclude='node_modules/' \
  --exclude='.yarn/' \
  --exclude='.pnp.*' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.venv/' \
  --exclude='.claude/' \
  --exclude='.impeccable/' \
  --exclude='*.sync-conflict-*' \
  --exclude='.git' \
  --exclude='dist/' \
  --exclude='.scrub' \
  --exclude='.publish-state.json' \
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

COMMIT_MSG="${2:-}"
if [[ -z "$COMMIT_MSG" ]]; then
  # `|| true` so a grep that matches nothing (e.g. only .gitignore staged)
  # doesn't trip `set -o pipefail` and abort the publish. Dot escaped so it
  # doesn't strip unrelated paths merely containing "gitignore".
  CHANGED_FILES=$(git diff --cached --name-only | { grep -v '\.gitignore' || true; } | head -5 | tr '\n' ', ' | sed 's/,$//')
  COMMIT_MSG="Update $SKILL_NAME: $CHANGED_FILES"
fi

echo ""
git commit -m "$COMMIT_MSG"
git push origin HEAD

# Record what was published so the next re-publish can scope its privacy review
# to only the files that changed (see changed-files.py). Written into the source
# skill dir and excluded from the published copy. Never fatal to the publish.
python3 "$SCRIPT_DIR/changed-files.py" --write "$SKILL_DIR" "$SKILL_DIR/.publish-state.json" || \
  echo "  (warning: could not write .publish-state.json manifest)" >&2

echo ""
echo "Published $SKILL_NAME to https://github.com/$REPO_FULL"
