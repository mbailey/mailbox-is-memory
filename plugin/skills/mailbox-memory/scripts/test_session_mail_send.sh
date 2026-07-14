#!/usr/bin/env bash
# Tests for session-mail-send's self-gated submission + case folding (COMS-86
# do-002 / design §4) and session-mail-wait's lowercase-fold-on-arm.
#
# Deterministic and side-effect-free: every maildir is a mktemp tree, and the
# smtp path is exercised against a STUB sendmail (a copy of the script with the
# absolute /usr/sbin/sendmail path swapped) — NO real mail is ever submitted.
#
# Run directly:
#   bash skills/session/scripts/test_session_mail_send.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SEND="$HERE/session-mail-send"
WAIT="$HERE/session-mail-wait"

pass=0; fail=0
ok(){ echo "  ok  $1"; pass=$((pass+1)); }
no(){ echo "FAIL  $1"; fail=$((fail+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$T/agents"

# --- CRIT 2+4: filedrop path → case fold + notice -----------------------------
# Force filedrop explicitly rather than relying on host state (no
# /etc/postfix/.session-mail-ready marker): this suite must be deterministic
# and side-effect-free on ANY host, including one that IS already
# postfix-migrated (verify-001 finding — on a migrated host the unforced
# default silently resolves to smtp and this block would pipe a real message
# through live sendmail instead of the filedrop path it's meant to test).
out="$(SESSION_MAIL_ROOT="$ROOT" SESSION_MAIL_TRANSPORT=filedrop bash "$SEND" "Foreman.COMS-86" \
        --from "worker.COMS-86" --subject "hi" -- "body text" 2>"$T/err")"
echo "$out" | grep -Eq '@.*\.session-mail>$' \
  && ok "filedrop: prints Message-ID" || no "filedrop: Message-ID not printed"
# Recipient here is UNQUALIFIED (no @host) — a same-host send, for which
# filedrop IS correct local delivery, so the cross-host degradation notice
# must NOT fire (COMS-95 same-host fix, session-mail-send ~L276-286: "an
# UNqualified <to> is a same-host send... no degradation, so no notice" —
# stale test expectation caught live by verify-001; the notice's actual
# cross-host trigger is exercised in the next block).
grep -Fq "cross-host mail NOT delivered from this host until migrated (wrote local copy to " "$T/err" \
  && no "filedrop: wrongly emitted the cross-host n2 notice for a same-host (unqualified) recipient" \
  || ok "filedrop: no cross-host n2 notice for a same-host recipient"
[ -d "$ROOT/foreman.coms-86/new" ] \
  && ok "filedrop: mailbox path folded to lowercase" || no "filedrop: lowercase path missing"

# --- CRIT 2+4b: filedrop path, CROSS-HOST-qualified recipient → n2 fires -----
# The load-bearing degradation notice IS scoped to a different-host-qualified
# <to> (design §4, do-006 n2 fix) — exercise that actual trigger directly.
# Own ROOT (ROOTX): the cross-host qualifier is stripped for local delivery
# (same LOCALPART, "foreman.coms-86"), so reusing $ROOT would drop a second,
# undrained message into the box the "wait" block below expects to be empty
# after its single claim.
ROOTX="$T/agentsx"
SESSION_MAIL_ROOT="$ROOTX" SESSION_MAIL_TRANSPORT=filedrop bash "$SEND" "Foreman.COMS-86@otherhost.example" \
        --from "worker.COMS-86" --subject "hi" -- "body text" >/dev/null 2>"$T/errx"
grep -Fq "cross-host mail NOT delivered from this host until migrated (wrote local copy to " "$T/errx" \
  && ok "filedrop: emits the exact load-bearing n2 notice for a cross-host recipient" \
  || no "filedrop: n2 notice missing/altered for a cross-host recipient"
[ "$(ls -1 "$ROOT")" = "foreman.coms-86" ] \
  && ok "filedrop: sole maildir entry is the lowercase name" || no "filedrop: unexpected entries: $(ls -1 "$ROOT")"

# --- CRIT 1: existing callers unchanged — wait fires + two-phase receipt ------
# Mixed-case listener name must resolve to the same lowercase box.
recv="$(SESSION_MAIL_ROOT="$ROOT" bash "$WAIT" "Foreman.COMS-86" --timeout 5 2>/dev/null)"
echo "$recv" | grep -q "Subject: hi" \
  && ok "wait: fires on delivery (mixed-case ME → lowercase box)" || no "wait: did not deliver"
[ -z "$(ls -A "$ROOT/foreman.coms-86/new/" 2>/dev/null)" ] \
  && ok "wait: new/ drained on claim" || no "wait: new/ not drained"
ls "$ROOT/foreman.coms-86/cur/" 2>/dev/null | grep -q ':2,S' \
  && ok "wait: claimed into cur/ with :2,S (two-phase / exactly-once)" || no "wait: :2,S flag missing"

# --- CRIT 3: smtp path performs NO maildir write (single-writer r05) ----------
STUB="$T/stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\ncat > "$SMTP_CAPTURE"\n' > "$STUB/sendmail"
chmod +x "$STUB/sendmail"
SMTP_SEND="$T/send-smtp"
sed "s#/usr/sbin/sendmail#$STUB/sendmail#" "$SEND" > "$SMTP_SEND"
ROOT2="$T/agents2"
export SMTP_CAPTURE="$T/captured.eml"
out2="$(SESSION_MAIL_ROOT="$ROOT2" SESSION_MAIL_TRANSPORT=smtp \
        bash "$SMTP_SEND" "Foreman.COMS-86" --from "worker.COMS-86" -- "smtp body" 2>"$T/err2")"
echo "$out2" | grep -Eq '@.*\.session-mail>$' \
  && ok "smtp: prints Message-ID" || no "smtp: Message-ID not printed"
[ ! -e "$ROOT2" ] \
  && ok "smtp: created NO maildir tree (single-writer r05)" || no "smtp: wrote a maildir: $(find "$ROOT2" 2>/dev/null)"
grep -q "smtp body" "$SMTP_CAPTURE" \
  && ok "smtp: message piped to sendmail -t" || no "smtp: sendmail received nothing"
grep -q "^To: Foreman.COMS-86$" "$SMTP_CAPTURE" \
  && ok "smtp: display To header keeps the caller's case" || no "smtp: To header case altered"
grep -Fq "cross-host mail NOT delivered" "$T/err2" \
  && no "smtp: wrongly emitted the filedrop notice" || ok "smtp: no filedrop notice"

# --- override + validation ----------------------------------------------------
ROOT3="$T/agents3"
SESSION_MAIL_ROOT="$ROOT3" SESSION_MAIL_TRANSPORT=filedrop \
  bash "$SEND" "x.y" --from a -- b >/dev/null 2>/dev/null
[ -d "$ROOT3/x.y/new" ] \
  && ok "override: SESSION_MAIL_TRANSPORT=filedrop forces filedrop" || no "override: filedrop not forced"
SESSION_MAIL_TRANSPORT=bogus bash "$SEND" "x.y" --from a -- b >/dev/null 2>"$T/verr"; rc=$?
{ [ "$rc" = 2 ] && grep -q "invalid SESSION_MAIL_TRANSPORT" "$T/verr"; } \
  && ok "override: invalid transport rejected (exit 2)" || no "override: invalid transport not rejected (rc=$rc)"

# --- help surface (regression: do-001 F1 — no shell-code leak) ----------------
bash "$SEND" --help | head -1 | grep -q "session-mail-send" \
  && ok "help: --help prints the header" || no "help: --help broken"
bash "$SEND" --help | grep -Eq "set -euo|^TO=|^case " \
  && no "help: --help leaks shell code past the comment header" || ok "help: --help stops at the comment header"

echo "----"
if [ "$fail" -eq 0 ]; then
  echo "ok - $pass session-mail-send tests passed"; exit 0
else
  echo "not ok - $fail of $((pass+fail)) session-mail-send tests failed"; exit 1
fi
