#!/usr/bin/env bash
# Tests for r07 read modes — session mail list / read (COMS-86 do-010, design §6
# D8). Deterministic and side-effect-free: every maildir is a mktemp tree seeded
# by session-mail-send's filedrop path. NO real mail is ever submitted.
#
# Run directly:
#   bash skills/session/scripts/test_session_mail_read_modes.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/session-mail"
SEND="$HERE/session-mail-send"
LIST="$HERE/session-mail-list"
READ="$HERE/session-mail-read"

pass=0; fail=0
ok(){ echo "  ok  $1"; pass=$((pass+1)); }
no(){ echo "FAIL  $1"; fail=$((fail+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$T/agents"

# Seed a mailbox for worker.coms-86 with three messages (filedrop = local write).
send() { SESSION_MAIL_ROOT="$ROOT" SESSION_MAIL_TRANSPORT=filedrop bash "$SEND" "$@" >/dev/null 2>&1; }
mid1="$(SESSION_MAIL_ROOT="$ROOT" SESSION_MAIL_TRANSPORT=filedrop bash "$SEND" worker.coms-86 --from cora --subject "first ping" -- "hello body one" 2>/dev/null)"
sleep 1  # distinct epoch prefixes ⇒ deterministic chronological ordering
send worker.coms-86 --from foreman.coms-86 --subject "second note" -- "the second message body"
sleep 1
# A reply to msg 1 — same thread (In-Reply-To chains Message-ID).
send worker.coms-86 --from cora --subject "re: first ping" --in-reply-to "$mid1" -- "reply in the thread"

# --- CRIT 1a: list shows sender+subject lines only, NO body -------------------
listout="$(SESSION_MAIL_ROOT="$ROOT" bash "$LIST" worker.coms-86 2>/dev/null)"
echo "$listout" | grep -q "first ping"   && ok "list: shows subject" || no "list: subject missing"
echo "$listout" | grep -q "cora"         && ok "list: shows sender"  || no "list: sender missing"
echo "$listout" | grep -q "hello body one" && no "list: LEAKED a body into the scan" || ok "list: no body in scan (low-context)"
echo "$listout" | grep -Eq "3 messages \(3 unread\)" && ok "list: summary counts messages+unread" || no "list: summary wrong: $(echo "$listout" | head -1)"

# --- CRIT 1b: read shows ONE body; no thread without the flag ----------------
r1="$(SESSION_MAIL_ROOT="$ROOT" bash "$READ" worker.coms-86 1 2>/dev/null)"
echo "$r1" | grep -q "hello body one" && ok "read: prints the message body" || no "read: body missing"
echo "$r1" | grep -q "Subject: first ping" && ok "read: prints a header block" || no "read: header block missing"
echo "$r1" | grep -q "reply in the thread" && no "read: pulled in the thread WITHOUT --thread" || ok "read: single message only (no implicit thread)"
echo "$r1" | grep -q "the second message body" && no "read: leaked an unrelated message" || ok "read: does not leak other messages"

# --- CRIT 1c: read --thread gathers the In-Reply-To chain --------------------
rt="$(SESSION_MAIL_ROOT="$ROOT" bash "$READ" worker.coms-86 1 --thread 2>/dev/null)"
{ echo "$rt" | grep -q "hello body one" && echo "$rt" | grep -q "reply in the thread"; } \
  && ok "read --thread: shows both messages in the thread" || no "read --thread: thread not assembled"
echo "$rt" | grep -q "the second message body" \
  && no "read --thread: wrongly included an unrelated message" || ok "read --thread: excludes unrelated mail"

# --- read is NON-DESTRUCTIVE: new/ not drained (wait's claim intact) ----------
before="$(ls -1 "$ROOT/worker.coms-86/new" | wc -l | tr -d ' ')"
SESSION_MAIL_ROOT="$ROOT" bash "$READ" worker.coms-86 1 >/dev/null 2>&1
after="$(ls -1 "$ROOT/worker.coms-86/new" | wc -l | tr -d ' ')"
[ "$before" = "$after" ] && [ "$after" = "3" ] \
  && ok "read: non-destructive (new/ still holds all 3 — wait's exactly-once claim intact)" \
  || no "read: disturbed new/ ($before -> $after)"

# --- list --unread filters to new/ only --------------------------------------
# Claim message 1 into cur/ (simulate a prior `wait`), then re-list.
f1="$(ls -1 "$ROOT/worker.coms-86/new" | sort | head -1)"
mv "$ROOT/worker.coms-86/new/$f1" "$ROOT/worker.coms-86/cur/${f1}:2,S"
allout="$(SESSION_MAIL_ROOT="$ROOT" bash "$LIST" worker.coms-86 2>/dev/null)"
unout="$(SESSION_MAIL_ROOT="$ROOT" bash "$LIST" worker.coms-86 --unread 2>/dev/null)"
echo "$allout" | grep -Eq "3 messages \(2 unread\)" && ok "list: default shows seen+unread, marks 2 unread" || no "list: default count wrong"
[ "$(echo "$unout" | grep -Ec '^\s*[0-9]+ ')" = "2" ] && ok "list --unread: shows only the 2 unread" || no "list --unread: wrong count"
# Index parity: message that moved new->cur keeps its list index (chronological).
idxout="$(SESSION_MAIL_ROOT="$ROOT" bash "$LIST" worker.coms-86 2>/dev/null | grep "first ping")"
echo "$idxout" | grep -Eq '^\s*1 ' && ok "list: index stable across new->cur move (parity with read)" || no "list: index shifted after claim"

# --- CRIT 3: case-insensitive resolution (mixed-case legacy + lowercase) ------
# 3a: caller uses mixed case, box is the canonical lowercase — resolves.
mc="$(SESSION_MAIL_ROOT="$ROOT" bash "$LIST" Worker.COMS-86 2>/dev/null)"
echo "$mc" | grep -q "first ping" && ok "resolve: mixed-case caller finds lowercase box" || no "resolve: mixed-case caller missed lowercase box"
# 3b: legacy mixed-case box on disk, caller uses lowercase — resolves.
ROOT2="$T/agents2"; LEGACY="$ROOT2/Legacy.Mixed"
mkdir -p "$LEGACY/new" "$LEGACY/cur" "$LEGACY/tmp"
printf 'From: someone\nSubject: legacy subject\n\nlegacy body\n' > "$LEGACY/new/1700000000.legacy.host"
leg="$(SESSION_MAIL_ROOT="$ROOT2" bash "$LIST" legacy.mixed 2>/dev/null)"
echo "$leg" | grep -q "legacy subject" && ok "resolve: lowercase caller finds legacy mixed-case box" || no "resolve: legacy box not resolved"
legr="$(SESSION_MAIL_ROOT="$ROOT2" bash "$READ" LEGACY.MIXED 1 2>/dev/null)"
echo "$legr" | grep -q "legacy body" && ok "resolve: read resolves legacy box case-insensitively" || no "resolve: read missed legacy box"

# --- empty mailbox is graceful -----------------------------------------------
empty="$(SESSION_MAIL_ROOT="$T/agents3" bash "$LIST" nobody.here 2>/dev/null)"; rc=$?
{ [ "$rc" = 0 ] && echo "$empty" | grep -q "no messages"; } && ok "list: empty mailbox → 'no messages', exit 0" || no "list: empty mailbox not handled"

# --- read: bad index rejected ------------------------------------------------
SESSION_MAIL_ROOT="$ROOT" bash "$READ" worker.coms-86 99 >/dev/null 2>"$T/e"; rc=$?
{ [ "$rc" = 2 ] && grep -q "no message at index 99" "$T/e"; } && ok "read: out-of-range index → exit 2" || no "read: bad index not rejected (rc=$rc)"
SESSION_MAIL_ROOT="$ROOT" bash "$READ" worker.coms-86 abc >/dev/null 2>"$T/e2"; rc=$?
{ [ "$rc" = 2 ] && grep -q "index must be a positive integer" "$T/e2"; } && ok "read: non-numeric index → exit 2" || no "read: non-numeric index not rejected (rc=$rc)"

# --- CRIT 2: verbs registered in the dispatcher help -------------------------
help="$(bash "$DISPATCH" --help 2>/dev/null)"
echo "$help" | grep -q "^  list " && ok "dispatch: list registered in --help" || no "dispatch: list missing from help"
echo "$help" | grep -q "^  read " && ok "dispatch: read registered in --help" || no "dispatch: read missing from help"
bash "$DISPATCH" bogusverb 2>"$T/uv" >/dev/null; echo "$(grep -o 'list, read' "$T/uv")" | grep -q "list, read" \
  && ok "dispatch: unknown-verb hint lists list+read" || no "dispatch: unknown-verb hint not updated"
# Routing: dispatcher execs the sibling scripts.
bash "$DISPATCH" list --help 2>/dev/null | grep -q "session-mail-list" && ok "dispatch: routes 'list' to session-mail-list" || no "dispatch: list routing broken"
bash "$DISPATCH" read --help 2>/dev/null | grep -q "session-mail-read" && ok "dispatch: routes 'read' to session-mail-read" || no "dispatch: read routing broken"

# --- CRIT 2: send/wait scripts UNTOUCHED by this slice -----------------------
# (guard: the two read verbs must not have edited the send/receive pair.)
bash "$SEND" --help 2>/dev/null | head -1 | grep -q "session-mail-send" && ok "send: --help still intact (untouched)" || no "send: help changed"
bash "$HERE/session-mail-wait" --help 2>/dev/null | grep -q "session-mail-wait" && ok "wait: --help still intact (untouched)" || no "wait: help changed"

# --- help surface (regression: no shell-code leak past the header) -----------
bash "$LIST" --help 2>/dev/null | grep -Eq "set -euo|^ROOT=|^while " && no "list: --help leaks shell code" || ok "list: --help stops at the comment header"
bash "$READ" --help 2>/dev/null | grep -Eq "set -euo|^ROOT=|^while " && no "read: --help leaks shell code" || ok "read: --help stops at the comment header"

echo "----"
if [ "$fail" -eq 0 ]; then
  echo "ok - $pass session-mail read-mode tests passed"; exit 0
else
  echo "not ok - $fail of $((pass+fail)) session-mail read-mode tests failed"; exit 1
fi
