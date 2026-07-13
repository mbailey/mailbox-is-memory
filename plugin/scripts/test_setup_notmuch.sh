#!/usr/bin/env bash
# Tests for do-005: setup.sh's fresh-machine notmuch bootstrap (foreman review
# BLOCKER on do-003 — a machine that has never run `notmuch setup` has no
# config file at all, and every `notmuch config get/set` silently no-ops
# against a nonexistent one, so the flagship `setup.sh all` quickstart broke
# at step 2 for exactly the fresh HN user).
#
# Each test runs in its own scratch $HOME + $NOTMUCH_CONFIG — never touches
# the real machine's notmuch config. Requires `notmuch` on PATH (skipped,
# not failed, if absent — same spirit as the other test_*.sh scripts, which
# assume their own runtime deps are present).
#
# Run directly:
#   bash plugin/scripts/test_setup_notmuch.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SETUP="$HERE/setup.sh"

pass=0; fail=0
ok(){ echo "  ok  $1"; pass=$((pass+1)); }
no(){ echo "FAIL  $1"; fail=$((fail+1)); }

if ! command -v notmuch >/dev/null 2>&1; then
    echo "SKIP: notmuch not on PATH — cannot exercise setup.sh notmuch"
    exit 0
fi

# --- 1. fresh machine: no config file anywhere notmuch would look ------------
t1="$(mktemp -d)"
(
    export HOME="$t1/home"
    export NOTMUCH_CONFIG="$t1/notmuchrc"
    mkdir -p "$HOME"
    "$SETUP" notmuch >/dev/null 2>&1
    got="$(notmuch config get database.path 2>/dev/null)"
    want="$HOME/.mail"
    [ "$got" = "$want" ] && echo OK || echo "FAIL got='$got' want='$want'"
) > "$t1/result"
if grep -q '^OK$' "$t1/result"; then
    ok "fresh machine: database.path bootstrapped to mailbox root"
else
    no "fresh machine: database.path not bootstrapped ($(cat "$t1/result"))"
fi
[ -f "$t1/notmuchrc" ] && ok "fresh machine: config file created at NOTMUCH_CONFIG path" \
    || no "fresh machine: config file missing after setup.sh notmuch"
rm -rf "$t1"

# --- 2. fresh machine: notmuch new / search round trip works after setup.sh -
t2="$(mktemp -d)"
(
    export HOME="$t2/home"
    export NOTMUCH_CONFIG="$t2/notmuchrc"
    export SESSION_MAIL_TRANSPORT=filedrop
    mkdir -p "$HOME"
    "$SETUP" all >/dev/null 2>&1
    SEND="$HERE/../skills/mailbox-memory/scripts/session-mail-send"
    bash "$SEND" memory --from tester "round trip probe" >/dev/null 2>&1
    notmuch new >/dev/null 2>&1
    notmuch search query:memory 2>/dev/null | grep -q tester && echo OK || echo FAIL
) > "$t2/result"
grep -q '^OK$' "$t2/result" \
    && ok "fresh machine: setup.sh all -> send -> notmuch new -> query:memory round trip" \
    || no "fresh machine: round trip failed"
rm -rf "$t2"

# --- 3. existing config: database.path left untouched (additive) ------------
t3="$(mktemp -d)"
(
    export HOME="$t3/home"
    export NOTMUCH_CONFIG="$t3/notmuchrc"
    mkdir -p "$HOME" "$t3/existing-mail"
    touch "$NOTMUCH_CONFIG"
    notmuch config set database.path "$t3/existing-mail" >/dev/null 2>&1
    "$SETUP" notmuch >/dev/null 2>&1
    got="$(notmuch config get database.path 2>/dev/null)"
    [ "$got" = "$t3/existing-mail" ] && echo OK || echo "FAIL got='$got'"
) > "$t3/result"
grep -q '^OK$' "$t3/result" \
    && ok "existing config: database.path unchanged (additive, no --force)" \
    || no "existing config: database.path was touched ($(cat "$t3/result"))"
rm -rf "$t3"

# --- 4. --dry-run touches nothing on a fresh machine -------------------------
t4="$(mktemp -d)"
(
    export HOME="$t4/home"
    export NOTMUCH_CONFIG="$t4/notmuchrc"
    mkdir -p "$HOME"
    "$SETUP" all --dry-run >/dev/null 2>&1
)
if [ -e "$t4/notmuchrc" ] || [ -e "$t4/home/.mail" ]; then
    no "dry-run: created files on a fresh machine"
else
    ok "dry-run: touches nothing on a fresh machine"
fi
rm -rf "$t4"

echo ----
if [ "$fail" -eq 0 ]; then
    echo "ok - $pass setup.sh notmuch bootstrap tests passed"
    exit 0
else
    echo "not ok - $fail of $((pass+fail)) setup.sh notmuch bootstrap tests failed"
    exit 1
fi
