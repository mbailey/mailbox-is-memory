---
name: mailbox-memory
description: >-
  Provision and use mailbox-memory — durable agent memory and comms over
  RFC 5322 mail in a maildir, indexed by notmuch. Use when the user (or
  agent) wants to "set up mailbox memory", "send myself a memory", asks
  "why isn't my agent mail arriving", or wants an agent to remember
  something across sessions by mailing itself.
---

# mailbox-memory

Companion plugin for the paper ["The Mailbox Is the
Memory"](https://github.com/mbailey/mailbox-is-memory): email as the
durable memory and comms substrate for LLM agents. This skill walks you
through provisioning it and sending yourself the first memory.

Scripts referenced below live inside this plugin — always invoke them
through `$CLAUDE_PLUGIN_ROOT` (an installed plugin does **not** put its
scripts on `PATH`):

- `$CLAUDE_PLUGIN_ROOT/scripts/setup.sh` — provisioning
- `$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-*` — the mail verbs

## 1. The model, in one paragraph

A message is an immutable, frozen fact — once sent, it never changes.
notmuch tags are mutable classification layered on top. Correcting or
retracting something is never an edit; it's a new message that
**supersedes** the old one (a retag, driven by a real `Supersedes:`
header, not a silent mutation). Remembering is mailing yourself: write
what you want to keep as a message to your own mailbox, and it's durable,
searchable, and survives losing the search index (step 5 proves this).

## 2. Provision

Everything below needs `notmuch` installed and nothing else — no root,
no postfix, no privileged paths (that's Tier 1; see step 7 for Tier 2).
Always look at `--dry-run` first so you know what it's about to touch:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/setup.sh" all --dry-run
"$CLAUDE_PLUGIN_ROOT/scripts/setup.sh" all
```

`all` runs `maildir` + `notmuch` + `autoindex`: creates
`~/.mail/agents/memory/{tmp,new,cur}`, configures notmuch (header
indexing, the `query:memory` saved search, and installs the post-new
auto-tag hook), and sets up a launchd (macOS) / systemd --user timer
(Linux) to run `notmuch new` on an interval. It's additive and
idempotent — safe to re-run, and it never overwrites an existing
`new.tags`/`query.memory` value without `--force`.

## 3. Send yourself a memory

```bash
"$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-send" \
  memory --from you@yourhost "first PoC memory"
```

Every send reports its transport (postfix/SMTP or local file-drop) on
stderr, and prints the message's Message-ID on stdout — note it, you'll
use it if you want to supersede this message later.

## 4. Read it back

```bash
"$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-list" memory
"$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-read" memory 1
```

`list` is a low-context scan (one line per message); `read` opens the
message at the index `list` printed. If you'd rather watch it arrive
live, run this in a second pane before sending — it blocks until a
message lands, then prints it and exits:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-wait" memory
```

## 5. Prove it survives losing the index

This is the paper's strongest claim (claim #2) made checkable in one
command: delete the notmuch index, rebuild it from the maildir alone,
and confirm a superseded memory *stays* superseded (the tag is a
projection of the mail, not the record itself — it's rederived from the
`Supersedes:` header at index time, so deleting the index can't erase a
correction). Deliberately destructive of the index only; it dumps and
restores your tags around the experiment, even on failure:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts/session-mail-rebuild-proof"
```

Exit 0 = the memory survived losing its own index. Exit 1 = it didn't —
a real falsification; don't paper over it.

## 6. Browse via `query:memory`

`setup.sh notmuch` (step 2) already wrote the saved search:

```bash
notmuch config set query.memory 'tag:memory and not tag:superseded'
```

so browsing current (non-superseded) memories is one command, from
anywhere notmuch is configured:

```bash
notmuch search query:memory
```

## 7. Tier 2 — postfix (optional, cross-host / multi-agent)

**You don't need this for the demo above.** Everything through step 6
runs on local file-drop delivery alone. Tier 2 is for when you want mail
to actually route through postfix — cross-host delivery, multiple agents
addressable by name, the full `<name>@<host>` picture. It's genuinely
system-level (writes under `/etc/postfix`, needs a running postfix) and
is opt-in only — `setup.sh all` never touches it:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/setup.sh" postfix --dry-run
```

See [`references/mail-troubleshooting.md`](references/mail-troubleshooting.md)
for the prerequisite, the map format, and how to trace a message end to
end when Tier 2 delivery doesn't behave.
