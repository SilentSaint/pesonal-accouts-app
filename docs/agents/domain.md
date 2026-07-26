# Domain Documentation

This repository uses a single-context domain documentation layout.

- **Layout**: `single-context`
- **Root Context**: `CONTEXT.md`
- **ADR Directory**: `docs/adr/`

## Consumer Rules for Agents

- Agents must read `CONTEXT.md` at the project root to understand the core domain concepts, ubiquitous language, and system architecture.
- Agents must consult Architectural Decision Records in `docs/adr/` before proposing structural, technical, or framework changes.
