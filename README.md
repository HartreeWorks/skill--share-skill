# Share Skill

A Claude Code skill for converting private skills into public GitHub repositories, making them shareable with the community.

## Documentation

See [SKILL.md](./SKILL.md) for complete documentation and usage instructions.

## Installation

```bash
npx skills add HartreeWorks/skill--share-skill
npx skills add HartreeWorks/skill--add-auto-update
```

Shared skills get update checks from [add-auto-update](https://github.com/HartreeWorks/skill--add-auto-update), so install it alongside.

## Updates

At most once a day, the skill checks for a new release. When there is one, your agent shows what changed, reviews the code changes, and asks whether to update now, update automatically from now on, or not now. Automatic updates wait three days after a release first appears. To stop the checks, ask your agent to run `scripts/check-update.sh --off`.

## About

Created by [Peter Hartree](https://x.com/peterhartree). For updates, follow [AI Wow](https://wow.pjh.is), my AI uplift newsletter.

Find more skills at [HartreeWorks/skills](https://github.com/HartreeWorks/skills).
