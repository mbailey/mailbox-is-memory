# Mail troubleshooting — tracing a message from sender to maildir

How to find out where an agent mail actually went. Written after an
incident (COMS-95, 2026-07-13) where an agent's mail "sent fine" and
silently vanished for hours.

**The one thing to internalise:** a mailbox *directory* existing does not mean
mail can be *delivered* to it. Those are two different facts, and the gap
between them is where messages disappear.

- **Watchable** = `~/.mail/agents/<name>/` exists → `session mail wait` can arm.
- **Deliverable** = `<name>@<host>` is in postfix's `virtual_mailbox_maps` → mail
  can arrive.

An agent can be **armed but unreachable** ("watch-only"): listening attentively
to a box that nothing can reach. It looks perfectly healthy from the inside.
That is the failure mode to suspect first when an agent "isn't getting mail".

---

## The trace: follow one message end to end

Run these in order. The first one that fails is your answer.

### 1. Is the recipient deliverable at all?

```bash
postmap -q "<name>@$(hostname -s)" hash:/etc/postfix/agents.d/vmailbox
```

Output = the maildir path → **deliverable**. No output → **not in the map**;
postfix will bounce mail to it as `unknown user`. Skip to
[map frozen / watch-only box](#map-frozen--watch-only-box).

Check what postfix itself believes, rather than trusting that path:

```bash
postconf -h virtual_mailbox_maps      # the enumerated maps, in lookup order
postconf -h recipient_delimiter       # '+' → strip +ext before you look up
```

> `virtual_mailbox_maps` is **enumerated** — there is no catch-all regexp
> (a regexp `$1` is forbidden in a path-result map, so the old catch-all was
> dead). Every single box must be listed, or it does not exist to postfix.

Since 2026-07-13, `session mail send` runs exactly this check **before**
submitting, and refuses with exit 3 rather than letting the message bounce.
If you got that refusal, believe it.

### 2. Did the message leave the sender?

`session mail send` prints its transport to stderr on every send:

```
session-mail-send: sent via smtp (postfix) → cora@host
session-mail-send: ⚠  FILEDROP — POSTFIX BYPASSED. Wrote the maildir directly: …
```

No line at all → the send died before transport (missing `--from`, bad flag).
Note the Message-ID on stdout; you will trace with it.

### 3. Is it stuck in the queue?

```bash
mailq                       # deferred mail, with the reason
postqueue -p                # same; works as any uid (postfix status is root-only)
```

A `Connection refused` to another host = the *remote* is down, not you.

### 4. Did it bounce? — **look in the SENDER's mailbox, not the recipient's**

This is the step everyone skips, and it is where the answer usually is.
Postfix returns undeliverable mail **to the sender**, so the evidence lands in
the mailbox of whoever the message was `--from`, which nobody thinks to read.

```bash
grep -rl "MAILER-DAEMON\|Undelivered Mail" ~/.mail/agents/<sender>/{new,cur} | tail -5
```

Then read one:

```bash
grep -iE "^Subject|^To:|unknown user|said:|5\.[0-9]\.[0-9]" <that-file>
```

`unknown user: <name>` = the recipient was not in the map (step 1).

### 5. Did it land?

```bash
ls ~/.mail/agents/<name>/new/    # delivered, unread
ls ~/.mail/agents/<name>/cur/    # claimed by a listener (`:2,S` = seen)
```

A message that moves `new/` → `cur/…:2,S` was **claimed by `session mail wait`** —
delivery *and* receipt both worked.

---

## Map frozen / watch-only box

**Symptom.** A newly created agent box is not in the map. Regenerating the
map (`setup.sh postfix`) hangs or fails silently. Mail to the agent bounces
`unknown user`, while the agent's listener sits armed and hears nothing.

**Why it happens.** `session-mail-wait` best-effort provisions the map entry
when it arms (provisioning = `mkdir` + map entry), looking for a
`vmailbox-gen`-shaped generator on `PATH` or under `~/.mail/.postfix/` — in
this plugin that's `setup.sh postfix` (above), not a standalone binary. The
call is bounded by a 10s watchdog so a wedged map dir can never block
arming — but if the generator isn't found, or it times out, the box still
arms, just **watch-only**: listening, with no map entry to actually receive
through. Since 2026-07-13 it says so, loudly. Older sessions did not.

**Diagnose.** Is the map stale?

```bash
/usr/bin/stat -f "map:     %Sm" /etc/postfix/agents.d/vmailbox   # BSD stat — see gotcha below
/usr/bin/stat -f "mailbox: %Sm" ~/.mail/agents/<name>
```

Mailbox newer than map → it never got provisioned.

**Fix — regenerate the map:**

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/setup.sh" postfix
postmap -q "<name>@$(hostname -s)" hash:/etc/postfix/agents.d/vmailbox   # verify
```

**If that hangs, the directory is wedged.** Probe it (never without a timeout):

```bash
timeout 5 mkdir /etc/postfix/agents.d/.probe && rmdir /etc/postfix/agents.d/.probe \
  && echo "clear" || echo "WEDGED"
```

A known wedge case (2026-07-13): every **write-open** on
`/etc/postfix/agents.d` hangs in-kernel, system-wide, while read-opens still
work — so the map keeps *serving* existing agents but can never be *updated*.
Nothing shows in `ps`; no process holds the lock.

- **Only a reboot clears it.** Then re-run `setup.sh postfix` and re-verify.
- **Meanwhile**, `--filedrop` delivers same-host mail without postfix. Read the
  next section before you reach for it.

---

## `--filedrop` is a backdoor. Use it knowing that.

`session mail send --filedrop` writes the recipient's maildir directly. Postfix
never sees the message. That means it:

- is **not logged** by the mail system — no record it ever existed;
- is **not cc'd** to the principal (Mike);
- **cannot cross hosts** — a `@other-host` recipient silently gets a useless
  local copy;
- **bypasses any content filtering**, including future prompt-injection
  screening. A path that skips the filter is worth exactly as much as an
  attacker's willingness to use it.

So: it is legitimate as a **deliberate, announced, local-only** delivery, and it
announces itself on every drop. It is **not** a way to route around a broken
map — that is what the pre-flight refusal exists to force you to fix. Never wire
it in as an automatic fallback for a bounce.

---

## Two agents, one role box — who gets the message?

Several sessions can be armed on the same role box (two Coras, two foremen). A
maildir claim is **exactly-once**, so without a rule they simply race, and the
message goes to whichever listener's watcher fires first — an operator can hit
this live: address a message to a *specific* session and a different one eats
it.

**Plus-addressing gives every session (or purpose) its own address for free.**
postfix strips the `+extension` before the map lookup, so `cora+cf138988@host`
and `cora+coms-110@host` both resolve through the single `cora@host` map row
and land in the one shared `agents/cora/` maildir.

- **The map does not grow.** One row per *role*, however many sessions run.
- **It needs no provisioning at all** — so direct session addressing works **even
  while the map dir is wedged**.
- postfix records the true envelope recipient in **`X-Original-To`** /
  **`Delivered-To`** (`enable_original_recipient = yes`), so the extension is
  preserved, greppable, and notmuch-indexable for correlation after the fact.
  (`To:` is only what the sender typed — prefer the envelope headers.)

**The claim rule** (`session mail wait`):

| Message addressed to | Who claims it |
|---|---|
| `cora` (bare role) | **any** role listener — this is the point of role addressing: a fresh session picks up the role's mail, nothing is lost when one dies |
| `cora+<my-ext>` | the listener armed as `cora+<my-ext>` — and **only** that: an extension arm is **strict**, it does not also swallow bare-role mail (asking for one address gives you that address and nothing else) |
| `cora+<my-session-id>` | a listener armed as bare `cora` **in that session** — one listener covers the role *and* its own direct address |
| `cora+<someone-else>` | **nobody else touches it.** It stays in `new/`, unclaimed, for the session it belongs to |

That last row is the whole safety property; without it, direct addressing is
decorative.

```bash
SD="$CLAUDE_PLUGIN_ROOT/skills/mailbox-memory/scripts"
"$SD/session-mail-wait" cora                  # "listen for both": role mail + mail for my own session
"$SD/session-mail-wait" cora+cf138988         # STRICT: only that address, no role mail
"$SD/session-mail-send" cora+cf138988 --from you "for you specifically"
```

⚠️ **Open:** mail addressed to a session that dies before reading it sits in
`new/` indefinitely. No adoption/TTL yet — deliberately parked (COMS-110).

---

## Gotchas

- **`stat -f` means different things on GNU and BSD.** On a host with GNU
  coreutils ahead of BSD on `PATH` (e.g. Homebrew `coreutils` unshimmed),
  `-f` is *filesystem status*, not format — so `stat -f %m` silently returns
  free-block counts, not an mtime. Use `/usr/bin/stat -f` (BSD) explicitly,
  or `stat -c` (GNU).
- **`postfix status` is root-only on macOS** and exits 1 *silently* for a
  non-root uid. Using it as a liveness probe degrades every agent send to
  filedrop. Probe with `postqueue -p` instead — setgid `postdrop`, works for
  any uid.
- **Addresses fold to lowercase** for path/lookup resolution; display headers
  keep their case.
- **Sibling names lie to you.** A similarly-named role being in the map
  tells you nothing about a different one. Check the exact name, not just
  the prefix.

---

## See also

- `../scripts/session-mail-send` — pre-flight, transports, and their reporting.
- `../scripts/session-mail-wait` — arming, provisioning, the watch-only warning.
- `../../../scripts/setup.sh postfix` — rebuilds the map from the maildir tree
  (single source of truth) and runs `postmap`.
- COMS-95 — the incident this document is made of.
