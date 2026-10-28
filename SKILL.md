---
name: share-skill
description: Publish a skill to a public GitHub repo.
---

# Share Skill

This skill publishes a private skill folder to a public GitHub repository, making it shareable with the community.

## What It Does

1. Validates the skill folder exists and has a SKILL.md file
2. **CRITICAL: Security & privacy review** — checks for credentials and private information
3. **Skill quality review** — invokes the `skill-creator` skill to check best practices
4. Creates or updates a README.md with a demo, installation, first prompt, and link to SKILL.md
5. Creates a public GitHub repo at `HartreeWorks/skill--{skill-name}` (if it doesn't exist)
6. Publishes using `publish-skill.sh` (rsyncs local → public excluding `data/` and private files, then applies global + per-skill deterministic scrub rules)
7. Adds update checks, so installed copies are offered each new release
8. Updates the public skills index at https://github.com/HartreeWorks/skills

## Prerequisites

- GitHub CLI (`gh`) must be installed and authenticated
- The skill folder must exist either globally (`~/.agents/skills/`, symlinked from `~/.claude/skills/`) or project-locally (`<project>/.claude/skills/`)
- The skill must have a `SKILL.md` file

## Workflow

When the user asks to share a skill, follow these steps:

### Before starting: check for updates

If `scripts/check-update.sh` exists in this skill's folder, run `bash <this skill's folder>/scripts/check-update.sh` from the user's project folder. It checks at most once a day and prints nothing when the skill is current.

- **It reports an update:** run it with `--diff` and read the code changes. Show the user the release notes and a short summary of the changes, flagging anything the notes do not explain. Ask whether to update now, update now and automatically from now on, or not now. For the first run it with `--apply`; for the second run it with `--enable-auto`, then `--apply`; for the third carry on.
- **It reports an automatic update:** run it with `--diff` and read the changes. If they match the release notes and do nothing risky, run it with `--apply` and tell the user in one line. Otherwise show the user your concerns and ask.
- **After `--apply` succeeds:** re-read this SKILL.md before continuing.

### Step 1: Resolve and Validate the Skill

Skills can live in two places:
- **Global:** `~/.agents/skills/<name>` (symlinked from `~/.claude/skills/<name>`)
- **Project-local:** `<project>/.claude/skills/<name>` (inside a specific project repo)

Resolve the skill path by checking both locations:

```bash
SKILL_NAME="skill-name-here"

# Prefer a project-local skill in the current working directory, then fall back
# to the global skills location.
if [ -d "$PWD/.claude/skills/$SKILL_NAME" ]; then
  SKILL_PATH="$PWD/.claude/skills/$SKILL_NAME"
elif [ -d "$HOME/.agents/skills/$SKILL_NAME" ]; then
  SKILL_PATH="$HOME/.agents/skills/$SKILL_NAME"
else
  echo "Skill '$SKILL_NAME' not found in project (.claude/skills) or global (~/.agents/skills)" >&2
fi

echo "Resolved skill path: $SKILL_PATH"

# Check SKILL.md exists
ls "$SKILL_PATH/SKILL.md"
```

If the user gave an explicit path to the skill folder, use that directly as `$SKILL_PATH` instead.

If the skill doesn't exist or has no SKILL.md, inform the user and stop.

**Name collision:** if the skill exists in *both* a project and the global location, they map to the same public repo (`skill--<name>`). Tell the user both were found and confirm which source to publish before proceeding.

### Step 2: Check if Already Shared

```bash
# Check if public repo already exists
gh repo view "HartreeWorks/skill--$SKILL_NAME" --json name 2>/dev/null && echo "Already shared" || echo "Not yet shared"
```

If already shared, ask the user if they want to re-publish (update the public repo). If yes, run the fast-path check (§3.0) to scope the review to what changed. If nothing private changed, go to Step 5 to refresh the README before publishing.

### Step 3: Security & Privacy Review (CRITICAL)

**This step is mandatory. Do NOT proceed to publishing without completing this review.**

#### 3.0: Fast path for an already-shared skill

Re-publishing a skill that has been shared before does **not** require re-reviewing every file. The deterministic scrub (§3b) re-applies every replacement agreed last time, and a manifest (`.publish-state.json`) records what was published. Scope the manual review to what actually changed:

```bash
python3 ~/.agents/skills/share-skill/scripts/changed-files.py "$SKILL_PATH"
```

Only **NEW** and **CHANGED** files need a fresh privacy scan (3a/3c); **UNCHANGED** files are covered by the last review plus the deterministic rules. If it reports "Nothing changed", go to Step 5 to check the README before publishing. If there is no manifest yet (first share, or a skill shared before this mechanism existed), every file is reported NEW: do the full review below, and publishing writes the manifest for next time.

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

#### 3b: Deterministic scrubbing (automatic, two tiers)

`publish-skill.sh` scrubs the published copy in two deterministic passes (via `scripts/scrub.py`), so agreed replacements never have to be re-derived:

1. **Global rules** — `~/.agents/skills/share-skill/scrub-rules.tsv`. Peter's unambiguous personal identifiers (home-directory paths, personal emails, phone numbers, calendar IDs), applied to *every* skill. Add a new always-private token here when you find one — but only things that are never a false positive. Do **not** add names ("Peter Hartree" must survive for README attribution), cities, client names, or project names.
2. **Per-skill `.scrub`** — an optional `<skill>/.scrub` file (TSV: `find<TAB>replace`, literal strings; a line starting with `#` is a comment unless it contains a tab, so rules can match Markdown headings). This is where the *context-specific* replacements from 3c get recorded: client/project names, sample data, location refs. Once written they re-apply automatically on every future publish. Both `.scrub` and the `.publish-state.json` manifest are excluded from the published copy.

**When you make a replacement in 3c for a skill you might update again, record it in `.scrub`** rather than only editing the file in place — that is what makes small refinements cheap to re-publish. Prefer `.scrub` over editing the private source whenever the source value is worth keeping (a real local path, a Peter-specific workflow note): the private source stays tailored to Peter, and only the published copy is genericised. To confirm a `.scrub` reproduces clean output, dry-run it: `rsync` the skill to a temp dir (excluding `.scrub`/`.publish-state.json`), run `scrub.py` with the global rules then the `.scrub`, and grep the result for private tokens.

#### 3c: Scan for Private Information in Text Files

Read through ALL text files in the skill folder, especially:
- `SKILL.md` - often contains examples
- Any `.md` files
- Script files with example data
- Template files

**Look for these types of private information:**

| Type | Examples | Replacement |
|------|----------|-------------|
| Client company names | 80,000 Hours, Acme Corp, etc. | HartreeWorks LTD |
| Real people's names (see note below) | Any real person's name | Clearly fictional names (Alice, Bob) or remove |
| Email addresses | john@client.com | alice@example.com |
| Slack workspace names | client-workspace | hartreeworks |
| Phone numbers | Any real numbers | +44 20 1234 5678 |
| URLs with client domains | client.slack.com | hartreeworks.slack.com |
| Project/internal names | Specific project codenames | Generic descriptions |

**Real people's names — CRITICAL:** Any name that refers to a real person MUST be replaced with a clearly fictional name (Alice, Bob, Jane Smith, etc.) before publishing. This includes names from the current conversation context — e.g., if you just summarised a call with someone, their name must not appear in examples added to the skill. When in doubt, treat a name as real. The test is: could someone Google this name and find a real person? If yes, replace it.

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

After the security review passes, check the skill against best practices before publishing. Invoke the `skill-creator` skill, scoped to review only:

```
Skill tool with skill: "skill-creator"
args: "Review $SKILL_PATH/SKILL.md for publication. Check description quality
       (third person, concrete trigger phrases), imperative writing style,
       progressive disclosure (SKILL.md lean, detail in references/), and that
       every referenced file and script path exists. Report findings only — do
       NOT run evals, generate test prompts, or rewrite the skill."
```

`skill-creator` is an eval-loop skill by default, so the review-only bound is load-bearing — if it starts drafting test prompts or offering to run a benchmark, stop it and review inline instead. If it is unavailable entirely, review inline against those same four criteria rather than skipping the step.

Use the resolved `$SKILL_PATH` from Step 1, not a hardcoded `~/.claude/skills` path.

Present the findings to the user. If there are issues rated as high-priority, fix them before proceeding. Minor suggestions can be noted but don't need to block publishing.

### Step 5: Create or update README.md

Create or update `$SKILL_PATH/README.md` for a human deciding whether to try the skill. Preserve useful existing explanations and examples; use the template as a baseline, refreshing outdated content on re-publication.

1. **Lead with the benefit.** Write a short description of what the reader can accomplish. Use the frontmatter as source material, rewriting agent-facing trigger phrases for humans.
2. **Use agent-neutral language.** Say "skill" and "your agent". Keep product names for product-specific dependencies and instructions, and describe actual requirements without promising universal compatibility.
3. **Show the core functionality near the top.** Usually include one or more screenshots of a real workflow or finished output, with short captions and useful alt text. For text-only skills, use a concise input/output example when it communicates more clearly than a screenshot. Capture safe example data; inspect every image for private information because text scrubbing cannot sanitise images. Save screenshots under `assets/` in the skill folder, outside the excluded `data/` directory, and use relative image links. If a real demonstration is unavailable, explain the gap to Peter rather than inventing one or publishing a broken placeholder.
4. **Make the first use easy.** Include installation, a copyable realistic prompt to give the agent, and the expected result. Mention material account, tool, operating-system, or paid-API requirements before installation; omit the requirements section when unnecessary.
5. **Finish with documentation and attribution.** Link to SKILL.md for full instructions and use the footer below, including both AI Wow and the shared skills index.

Adapt this template, replacing placeholders and omitting unnecessary sections:

````markdown
# {Skill name}

A skill for {concrete benefit}.

![{Description of the functionality or result shown}](./assets/{screenshot-filename}.png)

{Short caption explaining what the screenshot demonstrates.}

## Requirements

{Material prerequisites and costs, if any.}

## Installation

```bash
npx skills add HartreeWorks/skill--{skill-name}
```

## Try it

Ask your agent:

```text
{One realistic prompt the reader can copy.}
```

{Brief description of the expected result.}

## Documentation

See [SKILL.md](./SKILL.md) for complete documentation and usage instructions.

## About

Created by [Peter Hartree](https://x.com/peterhartree) of [AI Wow](https://wow.pjh.is).

Find more skills at [HartreeWorks/skills](https://github.com/HartreeWorks/skills).
````

Before publishing, check the README's examples and image links against the skill, and privacy-review any text or images created or changed in this step.

### Step 6: Create Public GitHub Repository (if needed)

```bash
REPO_NAME="skill--$SKILL_NAME"

# Create empty public repo (skip if already exists from Step 2)
gh repo create "HartreeWorks/$REPO_NAME" --public
```

### Step 7: Publish to Public Repo

Generate a concise commit message summarising the changes being published (e.g., "Split config into models.json + config.json overrides" or "Add brainstorm presets"), then pass it as the second argument:

```bash
# Publish using the publish script (rsyncs local → public, excluding data/ and private files)
# Pass the resolved $SKILL_PATH so project-local skills are found. The script
# accepts either a bare name (global) or a directory path (project-local).
bash ~/.agents/skills/share-skill/scripts/publish-skill.sh "$SKILL_PATH" "Brief description of what changed"
```

The publish script handles:
- Shallow-cloning the public repo to a temp dir
- Rsyncing local files, excluding `data/`, `.env`, `config.json`, `node_modules/`, etc.
- Ensuring `data/` is in the public repo's `.gitignore`
- Committing and pushing changes
- Cleaning up the temp dir

**Update checks (every shared skill).** Every shared skill is versioned and checks for updates; the add-auto-update skill holds the mechanism. Peter keeps it at `~/.agents/skills-unlisted/add-auto-update/`, outside the folders agents load skills from; anyone else installs it alongside this skill. A skill with a `VERSION` file gets the update scripts injected into its published copy on every publish. If the skill has no `VERSION` yet, before publishing follow steps 3 and 4 of that skill's "Add update checks": move user data out of the skill folder and add its snippets to SKILL.md and the README. Skip its `install.sh` and `release.sh` steps; this script does both. Then publish with `--release "Checks for updates"`, which creates `VERSION`.

Add `--release "<user-facing note>"` whenever the change is worth telling users about. It bumps `VERSION`, adds the note to `CHANGES.md` in the source, and tags the public commit `v<VERSION>`; commit `VERSION` and `CHANGES.md` afterwards. Leave the flag off for typo fixes and wording, which then reach users with the next release.

### Step 8: Update Public Skills Index

Add the new skill to the public skills index at `HartreeWorks/skills`.

```bash
INDEX_DIR="$HOME/.agents/skills/share-skill/skills-index"
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

### Step 9: Confirm Success

Output the public repository URL to the user:

```
✓ Skill "$SKILL_NAME" is now public!

Repository: https://github.com/HartreeWorks/skill--$SKILL_NAME
Skills index: https://github.com/HartreeWorks/skills

Others can follow the README to install it and try it with their agent.
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| Skill folder not found | Typo in skill name | Verify the skill name exists in `~/.claude/skills/` |
| No SKILL.md | Skill incomplete | Create a SKILL.md file first |
| Already shared | Public repo exists | Ask user if they want to re-publish |
| Privacy review failed | User chose to stop | User reviews files manually and runs share again |
| Sensitive files not in .gitignore | Missing .gitignore entries | Add entries to .gitignore before proceeding |
| gh auth error | Not logged in | Run `gh auth login` |
| Repo already exists | Name conflict | Check if repo exists at HartreeWorks |

## Example Usage

User: "Share the mochi-srs skill"

1. Validate: `~/.claude/skills/mochi-srs` exists with SKILL.md ✓
2. Check if `HartreeWorks/skill--mochi-srs` exists → not yet shared ✓
3. **Security & Privacy Review:**
   - Scan for sensitive files → found `config.json` (already in .gitignore ✓)
   - Scan text files for private info → found "80,000 Hours" in example
   - Report findings and suggest: "80,000 Hours" → "HartreeWorks LTD"
   - Ask user to approve changes
4. User approves → apply text replacements
5. **Skill Quality Review:** invoke `skill-creator` (review-only) → checks description, writing style, progressive disclosure
6. Create or update README.md following Step 5
7. Create `HartreeWorks/skill--mochi-srs` public repo
8. Publish using `publish-skill.sh` (rsyncs local → public, excluding `data/`)
9. Update skills index
10. Report success with the public URL

## Notes

- The GitHub organization is always `HartreeWorks`
- Repository naming follows the pattern `skill--{skill-name}`
- The skill folder name becomes the repo suffix
- **Always complete the security review before publishing** — never skip Step 3
- Default replacement for client company names: "HartreeWorks LTD"
- Default replacement for client emails: "alice@example.com"
- The `data/` directory is automatically excluded from public repos by `publish-skill.sh`
- To re-publish an existing skill, follow the fast path in §3.0 and refresh the README in Step 5 before running the publish command in Step 7.
