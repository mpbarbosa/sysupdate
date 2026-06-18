# Engineering Guides

These guides were imported and adapted from the sibling `doc_template_lib`
repository for `sysupdate`.

They are intentionally selective: this repo is a mixed Bash + Node/TypeScript
project with a stable CLI core, an active web dashboard, and significant
integration-boundary risk. Imported guides focus on those realities.

## Imported guides

| Guide | Why it fits `sysupdate` |
| --- | --- |
| [Clean Architecture Guide](./CLEAN_ARCHITECTURE_GUIDE.md) | The repo has a stable Bash core (`scripts/lib/`) with three distinct client layers (CLI, backend bridge, web dashboard). |
| [Code Quality Control Guide](./CODE_QUALITY_CONTROL_GUIDE.md) | Most risky changes cross Bash, backend bridge, and GUI boundaries simultaneously. |
| [High Cohesion Guide](./HIGH_COHESION_GUIDE.md) | `system_update.sh` must stay a thin orchestrator; each snippet must stay narrowly scoped to one tool. |
| [Low Coupling Guide](./LOW_COUPLING_GUIDE.md) | The web dashboard and future QuickShell widget must depend on the CLI JSON event contract, not duplicate update logic. |
| [DRY Guide](./DRY_GUIDE.md) | Shared helpers (`upgrade_utils.sh`), shared YAML config structure, and structured event contracts must stay single-source. |
| [Integration Test Guide](./INTEGRATION_TEST_GUIDE.md) | The main regression surface is the seam between CLI modules, the backend bridge, and GUI consumers — now covered by `tests/integration/` and `tests/backend/`. |
| [End-to-End Test Guide](./E2E_TEST_GUIDE.md) | The repo has assembled user-visible flows through the CLI and the web dashboard, though the formal E2E suite is still evolving. |
| [Unit Test Guide](./UNIT_TEST_GUIDE.md) | Two active unit test suites: BATS (`tests/bash/`) for core Bash functions and Vitest (`web/backend/utils.test.js`, `web/src/theme.test.ts`) for JS/TS helpers. |
| [Observability Guide](./OBSERVABILITY_GUIDE.md) | The structured JSON event stream (`emit_event`, `emit_summary_event`) is a first-class feature relied on by the backend bridge and dashboard. |
| [LLM Context Efficiency Guide](./LLM_CONTEXT_GUIDE.md) | Claude Code drives most development; snippet pattern consistency and `CLAUDE.md` files are the primary context management tools. |
| [Node.js Module Guide](./NODE_MODULE_GUIDE.md) | `web/backend/server.js` + `utils.js` follow a deliberate pure/effectful split that must be maintained. |
| [React Guide](./REACT_GUIDE.md) | `web/src/` has an active React 19 dashboard; `App.tsx` needs extraction as the feature set grows. |
| [Incremental Change Guide](./INCREMENTAL_CHANGE_GUIDE.md) | The CI/CD pipeline provides verification gates; all AI-assisted work should use the stacked change pattern. |
| [Naming Guide](./NAMING_GUIDE.md) | The mixed-language codebase (Bash, TypeScript, YAML, env vars, snippet IDs) needs explicit per-layer naming conventions. |
| [Error Handling Guide](./ERROR_HANDLING_GUIDE.md) | Errors span Bash exit codes, Node.js child process events, and React UI states — each layer has distinct handling rules. |
| [Claude Code Workflow Guide](./CLAUDE_CODE_WORKFLOW_GUIDE.md) | Operational patterns for Claude Code sessions: prompt construction, tool call review, verification rhythm, course correction, and commit discipline. |

## Not imported

| Template | Why it was not imported |
| --- | --- |
| `UNIT_TEST_GUIDE.md` → **imported** | Previously deferred ("import once unit tests exist"); BATS and Vitest suites now active. |
| `OBSERVABILITY_GUIDE.md` → **imported** | Previously not imported; `emit_event` / `emit_summary_event` JSON protocol now a core architectural feature. |
| `REFERENTIAL_TRANSPARENCY.md` | Partially covered by the Observability and Clean Architecture guides. `utils.js` pure-function split is the main application. Import if the pure functional core pattern becomes a recurring design pressure. |
| `DDD_GUIDE.md`, `LIGHTWEIGHT_DDD_GUIDE.md`, `DOMAIN_DESIGN_CONTROL_GUIDE.md` | `sysupdate` is a tool runner, not a domain-model-heavy application. Module boundaries explain the architecture better than DDD vocabulary. |
| `REST_API_GUIDE.md` | The local backend bridge is intentionally thin and local-only. REST design principles are not the primary pressure here. |
| `MOBILE_FIRST_GUIDE.md` | Not relevant to a Bash CLI with a desktop-oriented dashboard. |
| `SOLID_GUIDE.md` | The OO-centric framing does not map naturally to Bash + small Node.js modules. Relevant principles already appear in High Cohesion, Low Coupling, and Clean Architecture guides. |
| `INTERFACE_FIRST_GUIDE.md` | The JSON event schema is the key interface; it is covered adequately by the Observability and Incremental Change guides. Import if formal interface contracts become needed for new adapters. |
| `DEFENSIVE_CODING_GUIDE.md` | `sanitizeSnippetId` boundary validation is the main application of this guide. The Error Handling guide covers the boundary validation principle. Import if new user-input surfaces are added beyond snippet IDs. |

## How to use these guides here

1. Start with [Code Quality Control Guide](./CODE_QUALITY_CONTROL_GUIDE.md)
   for change review expectations.
2. Use [Clean Architecture](./CLEAN_ARCHITECTURE_GUIDE.md),
   [High Cohesion](./HIGH_COHESION_GUIDE.md), and
   [Low Coupling](./LOW_COUPLING_GUIDE.md) when deciding where code lives.
3. Use [Integration Test Guide](./INTEGRATION_TEST_GUIDE.md) and
   [Unit Test Guide](./UNIT_TEST_GUIDE.md) when changing library functions
   or adding snippets.
4. Use [Observability Guide](./OBSERVABILITY_GUIDE.md) when adding new
   snippet events or changing the JSON event schema.
5. Use [Node.js Module Guide](./NODE_MODULE_GUIDE.md) when changing
   `web/backend/`.
6. Use [React Guide](./REACT_GUIDE.md) when changing `web/src/`.
7. Use [Incremental Change Guide](./INCREMENTAL_CHANGE_GUIDE.md) for
   structuring Claude Code sessions.
8. Use [Claude Code Workflow Guide](./CLAUDE_CODE_WORKFLOW_GUIDE.md) for
   session-level operational patterns: prompt construction, reviewing tool
   calls, course correction, and commit discipline.
9. Use [Naming Guide](./NAMING_GUIDE.md) when adding env vars, snippet IDs,
   YAML keys, or TypeScript types.
10. Use [Error Handling Guide](./ERROR_HANDLING_GUIDE.md) when adding new
    snippet failure modes or backend route error responses.
11. Use [LLM Context Efficiency Guide](./LLM_CONTEXT_GUIDE.md) when
    `CLAUDE.md` files need updating or snippet patterns are diverging.

## Canonical command reference

- [`CLAUDE.md`](../../CLAUDE.md) — root-level commands (`system_update.sh` flags, `shellcheck`, `bats`)
- [`web/CLAUDE.md`](../../web/CLAUDE.md) — web commands (`npm run dev`, `npm run test`, `tsc --noEmit`)
