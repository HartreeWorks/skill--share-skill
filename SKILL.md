---
name: share-skill
description: This skill should be used when the user asks to "share a skill", "make a skill public", "publish a skill", "create a public repo for a skill", "convert skill to submodule", or mentions making a Claude Code skill available publicly. Converts a private skill folder into a public GitHub repository and Git submodule.
---

# Share Skill

This skill converts a private skill folder into a public GitHub repository, making it shareable with the community.

## What It Does

1. Validates the skill folder exists and has a SKILL.md file
2. **CRITICAL: Security & privacy review** — checks for credentials and private information
3. **Skill quality review** — runs the `plugin-dev:skill-reviewer` agent to check best practices
4. Creates a README.md with a link to SKILL.md
5. Adds update reminder section to SKILL.md (for auto-update system)
6. Initialises git in the skill folder
7. Creates a public GitHub repo at `HartreeWorks/skill--{skill-name}`
8. Pushes the skill to the public repo
9. Converts the local folder to a Git submodule
10. Updates the public skills index at https://github.com/HartreeWorks/skills

## Prerequisites

- GitHub CLI (`gh`) must be installed and authenticated
- The skill folder must exist in `~/.claude/skills/`
- The skill must have a `SKILL.md` file

## Workflow

When the user asks to share a skill, follow these steps:

### Step 1: Validate the Skill

```bash
SKILL_NAME="skill-name-here"
SKILLS_DIR=~/.claude/skills
SKILL_PATH="$SKILLS_DIR/$SKILL_NAME"

# Check skill folder exists
ls "$SKILL_PATH"

# Check SKILL.md exists
ls "$SKILL_PATH/SKILL.md"
```

If the skill doesn't exist or has no SKILL.md, inform the user and stop.

### Step 2: Check if Already Shared

```bash
# Check if already a submodule
grep -q "path = $SKILL_NAME" "$SKILLS_DIR/.gitmodules" 2>/dev/null && echo "Already a submodule" || echo "Not yet shared"
```

If already a submodule, inform the user and stop.

### Step 3: Security & Privacy Review (CRITICAL)

**This step is mandatory. Do NOT proceed to publishing without completing this review.**

#### 3a: Check for Sensitive Files

Look for files that might contain credentials or secrets:

```bash
# List all files in the skill folder
find "$SKILL_PATH" -type f -name "*.json" -o -name "*.env" -o -name ".env*" -o -name "*config*" -o -name "*secret*" -o -name "*credential*" -o -name "*token*" -o -name "*.key" -o -name "*.pem"
```

**Files that MUST NOT be committed:**
- `config.json` (often contains API tokens)
- `.env` or any `.env.*` files
- Any file with "secret", "credential", or "token" in the name
- Private keys (`.key`, `.pem`)
- Cache files with user data (e.g., `slack-cache-*.json`)

**Other files that should be excluded:**
- `.DS_Store` (macOS folder metadata)
- `.claude/` folder (local Claude Code settings/context)
- `__pycache__/` (Python bytecode cache)
- `node_modules/` (npm dependencies)
- `*.pyc` (Python compiled files)
- Any IDE/editor folders (`.idea/`, `.vscode/` with user settings)

**Action:** Ensure all of the above are listed in `.gitignore`. If no `.gitignore` exists, create one:

```bash
# Check for .gitignore
cat "$SKILL_PATH/.gitignore" 2>/dev/null || echo "No .gitignore found"
```

If missing or incomplete, create/update it before proceeding.

#### 3b: Scan for Private Information in Text Files

Read through ALL text files in the skill folder, especially:
- `SKILL.md` - often contains examples
- Any `.md` files
- Script files with example data
- Template files

**Look for these types of private information:**

| Type | Examples | Replacement |
|------|----------|-------------|
| Client company names | 80,000 Hours, Acme Corp, etc. | HartreeWorks LTD |
| Real people's names | John Smith, Sarah Connor | Generic names (Alice, Bob) or remove |
| Email addresses | john@client.com | alice@example.com |
| Slack workspace names | client-workspace | hartreeworks |
| Phone numbers | Any real numbers | +44 20 1234 5678 |
| URLs with client domains | client.slack.com | hartreeworks.slack.com |
| Project/internal names | Specific project codenames | Generic descriptions |

#### 3c: Report Findings to User

Present findings in a clear format:

```markdown
## Security & Privacy Review for {skill-name}

### Sensitive Files Found
- [ ] `config.json` - Contains API tokens - MUST be in .gitignore
- [ ] `cache.json` - Contains user data - MUST be in .gitignore

### Private Information Found

**SKILL.md line 45:**
> "Search for messages from 80,000 Hours workspace"
→ Suggest: "Search for messages from HartreeWorks Limited workspace"

**SKILL.md line 72:**
> "Example: john.doe@clientcompany.com"
→ Suggest: "Example: alice@example.com"

**scripts/example.py line 12:**
> workspace = "acme-corp"
→ Suggest: workspace = "hartreeworks"

### Required Actions
1. Add missing entries to .gitignore
2. Approve or modify the suggested text replacements
```

#### 3d: Wait for User Approval

**STOP and ask the user:**

Use AskUserQuestion:
```
question: "I've completed the security review. Should I make the suggested changes and proceed?"
header: "Review"
options:
  - label: "Apply changes & proceed"
    description: "Make all suggested replacements and continue publishing"
  - label: "Show me the changes first"
    description: "Display the exact edits before applying"
  - label: "Stop - I'll review manually"
    description: "Abort so you can review and edit files yourself"
multiSelect: false
```

**Only proceed to Step 5 after the user explicitly approves.**

If the user chooses "Apply changes & proceed":
1. Update `.gitignore` if needed
2. Make all suggested text replacements
3. Show a summary of changes made
4. Continue to Step 5

### Step 4: Skill Quality Review

After the security review passes, run the `plugin-dev:skill-reviewer` agent to check the skill against best practices before publishing. Use the Task tool:

```
Task tool with subagent_type: "plugin-dev:skill-reviewer"
prompt: "Review the skill at ~/.claude/skills/{SKILL_NAME}/SKILL.md for adherence to skill development best practices. Check: description quality (third-person, specific trigger phrases), writing style (imperative form), progressive disclosure (SKILL.md lean, details in references/), and that all referenced files exist."
```

Present the reviewer's findings to the user. If there are issues rated as high-priority, fix them before proceeding. Minor suggestions can be noted but don't need to block publishing.

### Step 5: Create README.md

Create a README.md in the skill folder that links to SKILL.md:

```markdown
# {Skill Name}

A Claude Code skill for {brief description from SKILL.md}.

## Documentation

See [SKILL.md](./SKILL.md) for complete documentation and usage instructions.

## Installation

```bash
npx skills add HartreeWorks/skill--{skill-name}
```

If you get "command not found", [install Node](https://github.com/HartreeWorks/skills/blob/main/how-to-install-node.md) then try again.

## About

Created by [Peter Hartree](https://x.com/peterhartree). For updates, follow [AI Wow](https://wow.pjh.is), my AI uplift newsletter.

Find more skills at [skills.sh](https://skills.sh) and [HartreeWorks/skills](https://github.com/HartreeWorks/skills).
```

**Extract the brief description** from the `description` field in the SKILL.md frontmatter.

### Step 5b: Add Update Reminder Section

Append the update reminder section to the end of SKILL.md (if not already present):

```bash
# Check if update section already exists
if ! grep -q "## Update check" "$SKILL_PATH/SKILL.md"; then
  cat >> "$SKILL_PATH/SKILL.md" << 'EOF'

## Update check

This skill is managed by [skills.sh](https://skills.sh). To check for updates, run `npx skills update`.
EOF
fi
```

This enables the auto-update reminder system for the newly shared skill.

### Step 7: Initialise git in skill folder

```bash
cd "$SKILL_PATH"

# Initialize if not already a git repo
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### Step 8: Create Public GitHub Repository

```bash
REPO_NAME="skill--$SKILL_NAME"

# Create public repo and push
gh repo create "HartreeWorks/$REPO_NAME" --public --source="$SKILL_PATH" --remote=origin --push
```

### Step 9: Convert to Submodule in Parent Repo

```bash
cd "$SKILLS_DIR"

# Remove the folder from git tracking (but keep files)
git rm -r --cached "$SKILL_NAME"

# Add as submodule
git submodule add "https://github.com/HartreeWorks/$REPO_NAME.git" "$SKILL_NAME"

# Commit the change
git add .gitmodules "$SKILL_NAME"
git commit -m "Convert $SKILL_NAME to public submodule

Public repo: https://github.com/HartreeWorks/$REPO_NAME

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### Step 10: Update Public Skills Index

Add the new skill to the public skills index at `HartreeWorks/skills`.

```bash
INDEX_DIR="$SKILLS_DIR/share-skill/skills-index"
cd "$INDEX_DIR"

# Pull latest
git pull origin main
```

Read the skill's SKILL.md to extract its description (from the frontmatter `description:` field).

Edit `README.md` to add a new row to the table in alphabetical order within the "Available skills" section. The table format is:

```markdown
| [skill-name](https://github.com/HartreeWorks/skill--{skill-name}) | {brief description} |
```

**Important:** Write a brief, clean description. Do NOT include trigger phrases (like "Use when the user says..."). Just describe what the skill does in one sentence.

Commit and push the index update:

```bash
git add README.md
git commit -m "Add {skill-name} skill

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
git push origin main
```

### Step 11: Confirm Success

Output the public repository URL to the user:

```
✓ Skill "$SKILL_NAME" is now public!

Repository: https://github.com/HartreeWorks/skill--$SKILL_NAME
Skills index: https://github.com/HartreeWorks/skills

Others can install it by pasting the repo URL into Claude Code.
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| Skill folder not found | Typo in skill name | Verify the skill name exists in `~/.claude/skills/` |
| No SKILL.md | Skill incomplete | Create a SKILL.md file first |
| Already a submodule | Already shared | The skill is already public |
| Privacy review failed | User chose to stop | User reviews files manually and runs share again |
| Sensitive files not in .gitignore | Missing .gitignore entries | Add entries to .gitignore before proceeding |
| gh auth error | Not logged in | Run `gh auth login` |
| Repo already exists | Name conflict | Check if repo exists at HartreeWorks |

## Example Usage

User: "Share the mochi-srs skill"

1. Validate: `~/.claude/skills/mochi-srs` exists with SKILL.md ✓
2. Check not already a submodule ✓
3. **Security & Privacy Review:**
   - Scan for sensitive files → found `config.json` (already in .gitignore ✓)
   - Scan text files for private info → found "80,000 Hours" in example
   - Report findings and suggest: "80,000 Hours" → "HartreeWorks LTD"
   - Ask user to approve changes
4. User approves → apply text replacements
5. **Skill Quality Review:** run `plugin-dev:skill-reviewer` agent → checks description, writing style, progressive disclosure
6. Create README.md linking to SKILL.md
7. Init git and commit
8. Create `HartreeWorks/skill--mochi-srs` public repo
9. Convert to submodule
10. Report success with the public URL

## Notes

- The GitHub organization is always `HartreeWorks`
- Repository naming follows the pattern `skill--{skill-name}`
- The skill folder name becomes the repo suffix
- **Always complete the security review before publishing** - never skip Step 3
- Default replacement for client company names: "HartreeWorks LTD"
- Default replacement for client emails: "alice@example.com"


## Update check

This skill is managed by [skills.sh](https://skills.sh). To check for updates, run `npx skills update`.

