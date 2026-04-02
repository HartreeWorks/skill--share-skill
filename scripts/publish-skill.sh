#!/bin/bash
# Publish a local skill to its public GitHub repo.
# Syncs all files except data/ and private files, then commits and pushes.
#
# Usage: publish-skill.sh <skill-name> [commit-message]
# Example: publish-skill.sh summarise-granola "Add new template support"
set -euo pipefail

SKILL_NAME="${1:?Usage: publish-skill.sh <skill-name>}"
SKILL_DIR="$HOME/.agents/skills/$SKILL_NAME"
REPO_NAME="skill--$SKILL_NAME"
REPO_FULL="HartreeWorks/$REPO_NAME"
TEMP_DIR=""

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
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
  --exclude='.env.local' \
  --exclude='.env.production' \
  --exclude='.env.development' \
  --exclude='config.json' \
  --exclude='node_modules/' \
  --exclude='__pycache__/' \
  --exclude='.venv/' \
  --exclude='.claude/' \
  --exclude='*.sync-conflict-*' \
  --exclude='.git' \
  --exclude='dist/' \
  "$SKILL_DIR/" "$TEMP_DIR/repo/" 2>&1 | sed 's/^/  /'

# Scrub personal email addresses from published files
echo "Scrubbing personal email addresses..."
find "$TEMP_DIR/repo" -type f \( -name "*.py" -o -name "*.md" -o -name "*.json" -o -name "*.sh" -o -name "*.ts" -o -name "*.js" \) \
  -not -path "*/.git/*" -exec sed -i '' \
  -e 's/pete\.hartree@gmail\.com/your-email@gmail.com/g' \
  -e 's/peter@type3\.audio/your-email@example.com/g' \
  -e 's/inboxwhenready@gmail\.com/your-product@gmail.com/g' \
  -e 's/p@pjh\.is/your-email@example.com/g' \
  -e 's/doctolib@pjh\.is/your-email@example.com/g' \
  {} +

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
  exit 0
fi

echo ""
echo "Changes to publish:"
git diff --cached --stat

COMMIT_MSG="${2:-}"
if [[ -z "$COMMIT_MSG" ]]; then
  CHANGED_FILES=$(git diff --cached --name-only | grep -v '.gitignore' | head -5 | tr '\n' ', ' | sed 's/,$//')
  COMMIT_MSG="Update $SKILL_NAME: $CHANGED_FILES"
fi

echo ""
git commit -m "$COMMIT_MSG"
git push origin HEAD

echo ""
echo "Published $SKILL_NAME to https://github.com/$REPO_FULL"
