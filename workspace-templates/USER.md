# USER.md - User Model

Store stable user preferences and profile facts as directives that can guide future sessions.

Use one directive per entry:

```md
<!-- observed: YYYY-MM-DD | status: active -->

- Prefer concise progress updates during implementation work.
```

- Begin each directive with an imperative such as `Always`, `Never`, or `Prefer`.
- Record the observation date and either `active` or `superseded` on the metadata line.
- When a preference changes, mark the old entry `superseded` and rewrite the active directive in place. Never append a contradictory active directive.
- Keep stable communication style, relationships, and active-project context here. Put durable non-profile facts and decisions in `MEMORY.md`.
- Save this file at the workspace root as `USER.md`. It loads every session with a separate 4,000-character budget.

## Directives

The directives below are generic defaults that ship with this workspace. They
describe no particular person: they are a starting point for any operator. Replace
or supersede them as you learn what this user actually prefers, following the rules
above. Never leave a placeholder directive `active`.

<!-- observed: 2026-11-02 | status: active -->

- Prefer concise replies and short progress updates; this agent is reached over a chat channel, where a wall of text is harder to read than a few short lines.

<!-- observed: 2026-11-02 | status: active -->

- Always say what you changed and what you verified, and state plainly when something failed or you skipped it.

## Related

- [Agent workspace](/concepts/agent-workspace)
