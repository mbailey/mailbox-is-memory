# mailbox-memory

**Email as durable memory and comms for LLM agents.** The Claude Code
plugin companion to the paper ["The Mailbox Is the
Memory"](../paper.md): provision a maildir + notmuch, mail yourself a
memory, read it back.

## Requirements

- `notmuch` — required (mail indexing, search, the `query:memory` view).
- `postfix` — optional, only needed for Tier 2 cross-host / multi-agent
  mail (see [`skills/mailbox-memory/SKILL.md`](skills/mailbox-memory/SKILL.md)
  step 7). Not required for the quickstart below.

## Installation

```bash
# 1. Add the marketplace (one-time)
/plugin marketplace add mbailey/mailbox-is-memory

# 2. Install the plugin
/plugin install mailbox-memory@mailbox-is-memory
```

No Claude Code? Clone the repo and run the setup script directly (from
the repo root):

```bash
git clone https://github.com/mbailey/mailbox-is-memory
cd mailbox-is-memory
./plugin/scripts/setup.sh all --dry-run   # see what it would do first
./plugin/scripts/setup.sh all             # maildir + notmuch + autoindex
```

## Basic usage

In a Claude Code session, ask your agent to set up mailbox memory — the
`mailbox-memory` skill triggers and walks you through provisioning and
your first send/read round trip:

```
set up mailbox memory
```

Or invoke it explicitly:

```
/mailbox-memory
```

The full 7-step walkthrough (the mental model, provisioning, send, read,
proving the memory survives losing the index, browsing via
`query:memory`, and optional Tier 2) lives in
[`skills/mailbox-memory/SKILL.md`](skills/mailbox-memory/SKILL.md) —
that's the depth this README stays out of.

Without an agent, the same round trip from a clone (repo-root-relative
paths, `you@yourhost` is a placeholder — use your own agent identity):

```bash
./plugin/skills/mailbox-memory/scripts/session-mail-send memory --from you@yourhost "first PoC memory"
./plugin/skills/mailbox-memory/scripts/session-mail-list memory
./plugin/skills/mailbox-memory/scripts/session-mail-read memory 1
```

## Commands

| Script | Does |
|---|---|
| `scripts/setup.sh maildir\|notmuch\|autoindex\|postfix\|all` | Provisioning — one entry point, `--dry-run` on every subcommand. `all` = maildir+notmuch+autoindex; `postfix` is opt-in Tier 2. |
| `skills/mailbox-memory/scripts/session-mail-send` | Send a message (`<to> --from <from> [--subject S] [--project P] [--task T] [--supersedes MSGID] <body...>`). |
| `skills/mailbox-memory/scripts/session-mail-wait` | Block until a matching message lands, claim it, print it. |
| `skills/mailbox-memory/scripts/session-mail-list` | Low-context scan — one line per message. |
| `skills/mailbox-memory/scripts/session-mail-read` | Open one message by the index `list` printed. |
| `skills/mailbox-memory/scripts/session-mail-rebuild-proof` | Delete the notmuch index, rebuild it, prove a superseded memory stays superseded. |

Full flag reference: run any script with `-h`/`--help`, or read the
comment header at the top of the script.

## See Also

- [`skills/mailbox-memory/SKILL.md`](skills/mailbox-memory/SKILL.md) — the full walkthrough.
- [`skills/mailbox-memory/references/mail-troubleshooting.md`](skills/mailbox-memory/references/mail-troubleshooting.md) — tracing a message end to end, Tier 2 gotchas.
- [`../paper.md`](../paper.md) — the paper this plugin is companion code for.
