# High Cohesion Guide

Use high cohesion in `sysupdate` so each script, snippet, backend module, and
document has one clear job.

## Goal

Keep related behavior together and unrelated behavior apart.

## What this means in `sysupdate`

Good cohesion in this repo usually looks like this:

- `scripts/system_update.sh` parses flags and orchestrates flows
- `scripts/lib/apt_manager.sh` owns APT-specific workflow
- one snippet owns one application or one narrow update surface
- `web/backend/server.js` owns local process execution and event streaming
- a guide in `docs/guides/` explains one engineering concern

If a file has to be described with repeated "and", it is probably too broad.

## Required rules

1. Keep one primary concern per script or document.
2. Do not let snippet files turn into ad hoc utility buckets.
3. Keep parsing, prompting, update logic, and UI state in the narrowest layer
   that actually owns them.
4. Shared helpers belong in `scripts/lib/`, not in one arbitrary snippet.
5. One guide should explain one principle or process area.

## Positive signals

- File names match their real responsibility.
- Snippet fixes usually stay inside one snippet or one shared helper.
- Web changes can often be explained as "backend contract" or "presentation
  mapping", not both at once.
- A document can be scanned without jumping between unrelated topics.

## Warning signs

- `system_update.sh` starts accumulating manager- or snippet-specific logic
- a single snippet both owns its tool-specific flow and several generic helpers
- `web/src/App.tsx` becomes the only place that knows everything about
  transport, mapping, inventory, prompts, and logging
- one doc mixes architecture, usage, troubleshooting, and change history

## Repo-specific examples

### Cohesive

- adding a shared version helper to `upgrade_utils.sh`
- keeping npm active-prefix logic in `update_npm.sh`
- keeping backend route handling in `web/backend/server.js`

### Not cohesive

- putting Cursor-specific version fallbacks in `core_lib.sh`
- embedding package-manager rules directly in the React UI
- copying generic prompt logic into several snippets

## Review heuristics

### One-sentence test

Can the file or document be described in one sentence without "and also"?

### Change-impact test

Would a change to one behavior force unrelated edits inside the same file? If
yes, the file may be carrying too many concerns.

## Related guides

- [LOW_COUPLING_GUIDE.md](./LOW_COUPLING_GUIDE.md)
- [DRY_GUIDE.md](./DRY_GUIDE.md)
- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md)

