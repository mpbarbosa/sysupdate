# Engineering Guides

These guides were imported and adapted from the sibling `doc_template_lib`
repository for `sysupdate`.

They are intentionally selective: this repo is a mixed Bash + Node/TypeScript
project with a stable CLI core, experimental GUI clients, and a lot of
integration-heavy change risk. The imported guides focus on those realities.

## Imported guides

| Guide | Why it fits `sysupdate` |
| --- | --- |
| [Clean Architecture Guide](./CLEAN_ARCHITECTURE_GUIDE.md) | The repo already has a stable core (`scripts/lib/`) with multiple entry points and clients. |
| [Code Quality Control Guide](./CODE_QUALITY_CONTROL_GUIDE.md) | Most risky changes cross Bash, backend bridge, and GUI boundaries. |
| [High Cohesion Guide](./HIGH_COHESION_GUIDE.md) | `system_update.sh` is intended to stay thin, and snippets should stay narrowly scoped. |
| [Low Coupling Guide](./LOW_COUPLING_GUIDE.md) | The web dashboard and QuickShell widget must depend on the CLI contract, not duplicate update logic. |
| [DRY Guide](./DRY_GUIDE.md) | The repo already relies on shared helpers, shared YAML config, and structured event contracts. |
| [Integration Test Guide](./INTEGRATION_TEST_GUIDE.md) | The main regression surface is the seam between CLI modules, snippets, the local backend bridge, and GUI consumers. |
| [End-to-End Test Guide](./E2E_TEST_GUIDE.md) | The repo has assembled user-visible flows through the CLI and the web dashboard, even though the formal E2E suite is still evolving. |

## Not imported now

| Template | Why it was not imported |
| --- | --- |
| `UNIT_TEST_GUIDE.md` | Useful in principle, but this repo does not currently have a checked-in unit test harness for the Bash core. Import it once unit-level automation exists. |
| `REFERENTIAL_TRANSPARENCY.md` | Some advice overlaps with the current repo, but it is not a strong enough fit to justify another cross-cutting guide yet. |
| `DDD_GUIDE.md`, `LIGHTWEIGHT_DDD_GUIDE.md`, `DOMAIN_DESIGN_CONTROL_GUIDE.md` | `sysupdate` is modular, but it is not a domain-model-heavy application. The architecture is better explained by module boundaries than by DDD vocabulary. |
| `REST_API_GUIDE.md` | The local backend bridge is intentionally thin and local-only; REST design is not the core design pressure in this repo. |
| `MOBILE_FIRST_GUIDE.md` | Not relevant to a Bash CLI plus desktop-oriented GUI experiments. |
| `ADR-FORMAT.md`, `CONTEXT-FORMAT.md` | The repo already has `docs/adr/` and a root `CONTEXT-MAP.md`; those existing conventions are sufficient for now. |

## How to use these guides here

1. Start with [Code Quality Control Guide](./CODE_QUALITY_CONTROL_GUIDE.md) for
   change review expectations.
2. Use [Clean Architecture Guide](./CLEAN_ARCHITECTURE_GUIDE.md),
   [High Cohesion Guide](./HIGH_COHESION_GUIDE.md), and
   [Low Coupling Guide](./LOW_COUPLING_GUIDE.md) when deciding where code or
   docs should live.
3. Use [Integration Test Guide](./INTEGRATION_TEST_GUIDE.md) and
   [End-to-End Test Guide](./E2E_TEST_GUIDE.md) when changes touch the CLI
   contract, the local backend bridge, or GUI flows.

Repository-specific command truth still lives in:

- [`README.md`](../../README.md) for project-level usage
- [`CLAUDE.md`](../../CLAUDE.md) for architecture and validation commands
- [`web/README.md`](../../web/README.md) for the local backend bridge
