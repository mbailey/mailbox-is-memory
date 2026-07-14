#!/usr/bin/env bash
#
# setup.sh — one entry point for provisioning mailbox-memory (SESH-86).
#
# Four mechanical pieces, one script, subcommands instead of four separate
# entry points (lower cognitive load for a first-time cloner):
#
#   setup.sh maildir   [--root DIR] [--name NAME]... [--dry-run]
#   setup.sh notmuch   [--dry-run] [--force] [--hooks-dir DIR]
#   setup.sh autoindex [--dry-run] [--interval SECONDS] [--label NAME]
#   setup.sh postfix   [--dry-run] [--print] [--host NAME] [--root DIR]
#                      [--magicdns-suffix SUFFIX] [--out FILE] [--no-postmap]
#   setup.sh all       [--dry-run]     # maildir + notmuch + autoindex, NOT postfix
#
# TWO TIERS (design.md §1). Tier 1 — maildir + notmuch + autoindex — gets you
# to "mail yourself a memory and read it back" with nothing beyond `notmuch`
# installed: no root, no privileged paths, no postfix. This is what `all`
# runs. Tier 2 — postfix — is cross-host/multi-agent mail; it is genuinely
# system-level (writes under /etc/postfix, needs a running postfix) and is
# deliberately OPT-IN: `all` never runs it, you ask for it by name.
#
# Every subcommand takes --dry-run: prints every action it would take and
# touches NO files, runs NO commands with side effects. Every subcommand is
# idempotent — safe to re-run.
#
# Pattern followed: skills/road-location/scripts/install.sh (parametrized
# flags, each with an env-var override; patch the INSTALLED copy of a vendored
# file rather than the source; --dry-run mirrors real output 1:1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$PLUGIN_ROOT/skills/mailbox-memory"

DRY_RUN=0

die() { printf 'setup.sh: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# run CMD... — echo under --dry-run, otherwise execute. Shared by every
# subcommand so `--dry-run` behaves identically everywhere.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  + %s\n' "$*"
    else
        "$@"
    fi
}

# ----------------------------------------------------------------------------
# maildir — mkdir ~/.mail/agents/<name>/{tmp,new,cur} for each --name
# ----------------------------------------------------------------------------
cmd_maildir() {
    local root="${MAILBOX_MEMORY_ROOT:-$HOME/.mail}"
    local names=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --root)     root="${2:?--root needs a value}"; shift 2 ;;
            --name)     names+=("${2:?--name needs a value}"); shift 2 ;;
            --dry-run)  DRY_RUN=1; shift ;;
            -h|--help)  usage; exit 0 ;;
            *)          die "maildir: unknown argument: $1 (try --help)" ;;
        esac
    done

    # Default box: "memory" — the shared demo mailbox the SKILL/quickstart
    # send the first message to (`session-mail-send memory --from you ...`).
    [ ${#names[@]} -gt 0 ] || names=(memory)

    echo "[maildir] root: $root"
    [ "$DRY_RUN" = 1 ] && echo "[maildir] MODE: DRY-RUN (no changes)"

    local name box
    for name in "${names[@]}"; do
        box="$root/agents/$name"
        echo "[maildir] provisioning $box/{tmp,new,cur}"
        run mkdir -p "$box/tmp" "$box/new" "$box/cur"
    done
}

# ----------------------------------------------------------------------------
# notmuch — additive config + install the post-new hook
# ----------------------------------------------------------------------------

# notmuch_get KEY — current value, empty if unset/notmuch not configured yet.
notmuch_get() {
    notmuch config get "$1" 2>/dev/null || true
}

# notmuch_config_path — where notmuch itself will look for its config file,
# per its own documented search order (skipping the `--config` CLI flag,
# which setup.sh never passes): NOTMUCH_CONFIG env override, else the XDG
# default-profile path, else the legacy $HOME/.notmuch-config[.PROFILE].
# Used only to detect "does a config file exist at all" (do-005 bootstrap
# below) — never to second-guess notmuch's own resolution once one exists.
notmuch_config_path() {
    if [ -n "${NOTMUCH_CONFIG:-}" ]; then
        printf '%s\n' "$NOTMUCH_CONFIG"
        return
    fi
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local profile="${NOTMUCH_PROFILE:-default}"
    local xdg_path="$xdg/notmuch/$profile/config"
    local legacy_path="$HOME/.notmuch-config"
    [ -n "${NOTMUCH_PROFILE:-}" ] && legacy_path="$HOME/.notmuch-config.$NOTMUCH_PROFILE"
    if [ -f "$xdg_path" ]; then
        printf '%s\n' "$xdg_path"
    elif [ -f "$legacy_path" ]; then
        printf '%s\n' "$legacy_path"
    else
        # Neither exists — this is the fresh-machine case (no `notmuch setup`
        # ever run). Nominate the modern XDG path as where we'll bootstrap.
        printf '%s\n' "$xdg_path"
    fi
}

# notmuch_set_additive KEY VALUE LABEL FORCE — set KEY=VALUE unless a
# DIFFERENT value is already present, in which case skip (or overwrite with
# --force). Never clobbers a user's existing new.tags/query.memory silently.
notmuch_set_additive() {
    local key="$1" value="$2" label="$3" force="$4" current
    current="$(notmuch_get "$key")"
    if [ -z "$current" ] || [ "$current" = "$value" ]; then
        echo "[notmuch] $label: setting $key = $value"
        run notmuch config set "$key" "$value"
    elif [ "$force" = 1 ]; then
        echo "[notmuch] $label: overwriting existing $key ('$current' -> '$value') [--force]"
        run notmuch config set "$key" "$value"
    else
        echo "[notmuch] $label: leaving existing $key = '$current' untouched (differs from '$value'; pass --force to overwrite)"
    fi
}

# notmuch_set_new_tags FORCE TAG... — additive setter for the list-type
# new.tags config key. `notmuch config get new.tags` returns one tag per
# line, not space-separated, so it needs its own compare/set logic instead of
# notmuch_set_additive's single-value string compare.
notmuch_set_new_tags() {
    local force="$1"; shift
    local want=("$@")
    local current=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && current+=("$line")
    done < <(notmuch_get new.tags)

    local want_joined current_joined
    want_joined="$(printf '%s ' "${want[@]}")"
    current_joined="$(printf '%s ' "${current[@]+"${current[@]}"}")"

    if [ ${#current[@]} -eq 0 ] || [ "$current_joined" = "$want_joined" ]; then
        echo "[notmuch] new-mail tags: setting new.tags = ${want[*]}"
        run notmuch config set new.tags "${want[@]}"
    elif [ "$force" = 1 ]; then
        echo "[notmuch] new-mail tags: overwriting existing new.tags ('${current[*]}' -> '${want[*]}') [--force]"
        run notmuch config set new.tags "${want[@]}"
    else
        echo "[notmuch] new-mail tags: leaving existing new.tags = '${current[*]}' untouched (differs from '${want[*]}'; pass --force to overwrite)"
    fi
}

# bootstrap_set_database_path VALUE — the first-ever `notmuch config set`
# call against a brand-new EMPTY config prints "Error: could not locate
# database." to stderr, regardless of which key is being set, and keeps
# printing it on every subsequent call until database.path itself has
# successfully been written once — even though every one of those calls
# still exits 0 and the value IS written (verified live, notmuch 0.40; do-003
# / SESH-92 rehearsal Finding C). It reads exactly like a failure to an
# unassisted eye scanning setup output on a truly fresh machine, so swallow
# that one known-benign line here (this is the FIRST config-set call setup.sh
# ever makes on a freshly-bootstrapped config, so it's the one call that can
# hit it) and print a one-line explanation instead of the raw notmuch error.
bootstrap_set_database_path() {
    local value="$1" out
    if [ "$DRY_RUN" = 1 ]; then
        printf '  + notmuch config set database.path %s\n' "$value"
        return 0
    fi
    out="$(notmuch config set database.path "$value" 2>&1 1>/dev/null)" || true
    if [ -n "$out" ]; then
        if [ "$out" = "Error: could not locate database." ]; then
            echo "[notmuch]   (harmless: notmuch prints that line on the very first config write to a brand-new config, before the database itself exists — the value is set correctly, exit 0)"
        else
            printf '%s\n' "$out" >&2
        fi
    fi
}

cmd_notmuch() {
    local force=0
    local hooks_dir=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --force)      force=1; shift ;;
            --hooks-dir)  hooks_dir="${2:?--hooks-dir needs a value}"; shift 2 ;;
            --dry-run)    DRY_RUN=1; shift ;;
            -h|--help)    usage; exit 0 ;;
            *)            die "notmuch: unknown argument: $1 (try --help)" ;;
        esac
    done

    command -v notmuch >/dev/null 2>&1 || die "notmuch: 'notmuch' not found on PATH — install it first"

    [ "$DRY_RUN" = 1 ] && echo "[notmuch] MODE: DRY-RUN (no changes)"

    local mailbox_root="${MAILBOX_MEMORY_ROOT:-$HOME/.mail}"

    # Fresh-machine bootstrap (foreman review BLOCKER, do-005): `notmuch
    # config get/set` are silent no-ops when NO config file exists yet at
    # ALL — verified live (notmuch 0.40): with NOTMUCH_CONFIG pointed at a
    # path that doesn't exist, `notmuch config set database.path ...` prints
    # "Error: could not locate database." to stderr and writes nothing (exit
    # 0 either way), so every additive setter below — and the final
    # `notmuch new` this quickstart depends on — silently fails on any
    # machine that has never run `notmuch setup`. The flagship `setup.sh all`
    # broke at exactly this step for a truly fresh HN user.
    #
    # Once a config file exists (even an EMPTY one — verified live), the
    # exact same `notmuch config set` calls work normally. So the fix is
    # narrow: if notmuch's own search order finds no config file, create an
    # empty one at the path it would use, and make sure the mailbox root dir
    # exists. This never touches an existing config: the `-f` check only
    # fires when nothing is there yet.
    local cfg_path bootstrapped=0
    cfg_path="$(notmuch_config_path)"
    if [ ! -f "$cfg_path" ]; then
        echo "[notmuch] no existing config found (checked \$NOTMUCH_CONFIG, XDG default, ~/.notmuch-config) — bootstrapping fresh config at $cfg_path (mailbox root: $mailbox_root)"
        run mkdir -p "$(dirname "$cfg_path")"
        run mkdir -p "$mailbox_root"
        if [ "$DRY_RUN" = 1 ]; then
            printf '  + touch %s\n' "$cfg_path"
        else
            touch "$cfg_path"
        fi
        bootstrapped=1
    fi

    # database location: deliberately NOT routed through notmuch_set_additive
    # — verified live that `notmuch config get database.path` never returns
    # empty once a config file exists at all, even one with the key never
    # set: it falls back to notmuch's OWN computed default (its documented
    # DATABASE LOCATION search order, e.g. $HOME/mail) and prints that as the
    # "current" value. notmuch_set_additive's emptiness check would read
    # that computed default as "already configured" and skip setting it —
    # silently leaving the just-bootstrapped config pointed at notmuch's
    # default instead of our mailbox root, so `notmuch new`/`search` would
    # never see mail written under $MAILBOX_MEMORY_ROOT (verified live: the
    # send/search round trip found 0 messages before this fix). Gate on the
    # file-existence bootstrap flag above instead, which is the only
    # reliable "was there ever a real config" signal. mail_root is set
    # alongside database.path — newer notmuch defaults mail_root from
    # database.path when unset, but the do-005 remit calls out setting it
    # explicitly for notmuch versions that want it set directly.
    if [ "$bootstrapped" = 1 ]; then
        echo "[notmuch] database root: setting database.path = $mailbox_root (fresh config)"
        bootstrap_set_database_path "$mailbox_root"
        echo "[notmuch] database root (mail_root): setting database.mail_root = $mailbox_root (fresh config)"
        run notmuch config set database.mail_root "$mailbox_root"
    elif [ "$force" = 1 ]; then
        local current_path current_mail_root
        current_path="$(notmuch_get database.path)"
        current_mail_root="$(notmuch_get database.mail_root)"
        echo "[notmuch] database root: overwriting existing database.path ('$current_path' -> '$mailbox_root') [--force]"
        run notmuch config set database.path "$mailbox_root"
        echo "[notmuch] database root (mail_root): overwriting existing database.mail_root ('$current_mail_root' -> '$mailbox_root') [--force]"
        run notmuch config set database.mail_root "$mailbox_root"
    else
        echo "[notmuch] database root: existing config found at $cfg_path — leaving database.path/mail_root untouched (pass --force to overwrite)"
    fi

    # Header indexing: makes the X-Task/X-Project/Supersedes prefixes
    # (design §5's requirement) queryable without a corpus grep, and gives
    # notmuch-post-new's Supersedes re-derivation a scale-out path later
    # (index the header instead of grepping the corpus).
    #
    # Prefix names (the LEFT side, `index.header.<prefix>`) are xapian query
    # prefixes, not header names — notmuch rejects a hyphen in one ("Prefix
    # names starting with lower case letters are reserved" / non-word char
    # errors verified live against notmuch 0.40). So X-Task/X-Project index
    # under the hyphen-free prefixes XTask/XProject (`notmuch search
    # XTask:SESH-86`); the header actually indexed (the RIGHT side, the
    # value) is still the real `X-Task`/`X-Project` header. Supersedes has no
    # hyphen so prefix == header name.
    notmuch_set_additive index.header.XTask       X-Task      "header indexing" "$force"
    notmuch_set_additive index.header.XProject    X-Project   "header indexing" "$force"
    notmuch_set_additive index.header.Supersedes  Supersedes  "header indexing" "$force"

    # The saved search the quickstart/SKILL point at (`query:memory`).
    notmuch_set_additive query.memory "tag:memory and not tag:superseded" "saved search" "$force"

    # new.tags: additive only — don't fight the user's existing base config,
    # design §4/§9 open question 3. new.tags is a LIST-type config key, not a
    # single string: `notmuch config get new.tags` returns one tag per line
    # (newline-separated, verified live: "unread\ninbox\n"), and `notmuch
    # config set new.tags` takes each tag as its own argument — joining them
    # into one space-separated argument would set a single literal tag
    # containing a space instead of two tags (foreman review). Handled by a
    # dedicated list-aware setter rather than notmuch_set_additive.
    notmuch_set_new_tags "$force" unread inbox

    # Install the post-new hook. Resolve hooks.dir the way notmuch itself
    # does: explicit --hooks-dir override, else the real config key
    # database.hook_dir (NOT "hooks.dir" — that key does not exist; verified
    # live that `notmuch config get hooks.dir` is silently empty while
    # `database.hook_dir` returns the real path — foreman review), else
    # <database.path>/.notmuch/hooks.
    if [ -z "$hooks_dir" ]; then
        hooks_dir="$(notmuch_get database.hook_dir)"
    fi
    if [ -z "$hooks_dir" ]; then
        local db_path
        db_path="$(notmuch_get database.path)"
        [ -n "$db_path" ] || db_path="$mailbox_root"
        hooks_dir="$db_path/.notmuch/hooks"
    fi

    local hook_src="$SKILL_DIR/hooks/notmuch-post-new"
    local hook_dst="$hooks_dir/post-new"
    [ -f "$hook_src" ] || die "notmuch: missing source hook: $hook_src"

    echo "[notmuch] installing post-new hook -> $hook_dst"
    run mkdir -p "$hooks_dir"

    # Portable notmuch binary resolution (foreman review gap #2): the
    # vendored hook hardcodes /opt/homebrew/bin/notmuch (needed under
    # launchd, whose PATH lacks /opt/homebrew/bin — see the hook's own
    # comment). Patch the INSTALLED copy to the notmuch actually on this
    # machine's PATH; the vendored source in the plugin stays pristine, same
    # spirit as install.sh's --port/--home overrides.
    #
    # `sed -e ... SRC > DST` (copy-via-transform, no `-i`) rather than
    # `cp` + `sed -i` on purpose: `sed -i` is spelled differently on BSD vs
    # GNU sed (`-i ''` vs `-i`), and on this machine `sed` on PATH already
    # resolves to GNU sed (homebrew gnu-sed ahead of /usr/bin) — `sed -i ''`
    # fails there with "can't read : No such file or directory" (verified
    # live). A redirect avoids the flag entirely and works identically on
    # both.
    local notmuch_bin
    notmuch_bin="$(command -v notmuch)"
    if [ "$DRY_RUN" = 1 ]; then
        printf '  + sed -e "s|^NOTMUCH=.*|NOTMUCH=%s|" %s > %s\n' "$notmuch_bin" "$hook_src" "$hook_dst"
        printf '  + chmod +x %s\n' "$hook_dst"
    else
        sed -e "s|^NOTMUCH=.*|NOTMUCH=$notmuch_bin|" "$hook_src" > "$hook_dst"
        chmod +x "$hook_dst"
    fi
}

# ----------------------------------------------------------------------------
# autoindex — launchd (macOS) / systemd --user timer (Linux) running
# `notmuch new` on an interval.
# ----------------------------------------------------------------------------
cmd_autoindex() {
    local interval=300
    local label="com.mailboxmemory.notmuch-new"

    while [ $# -gt 0 ]; do
        case "$1" in
            --interval) interval="${2:?--interval needs a value}"; shift 2 ;;
            --label)    label="${2:?--label needs a value}"; shift 2 ;;
            --dry-run)  DRY_RUN=1; shift ;;
            -h|--help)  usage; exit 0 ;;
            *)          die "autoindex: unknown argument: $1 (try --help)" ;;
        esac
    done

    case "$interval" in ''|*[!0-9]*) die "autoindex: --interval must be an integer, got: $interval" ;; esac

    command -v notmuch >/dev/null 2>&1 || die "autoindex: 'notmuch' not found on PATH — install it first"

    [ "$DRY_RUN" = 1 ] && echo "[autoindex] MODE: DRY-RUN (no changes)"

    local os
    os="$(uname)"
    case "$os" in
        Darwin) autoindex_macos "$interval" "$label" ;;
        Linux)  autoindex_linux "$interval" "$label" ;;
        *)      die "autoindex: unsupported OS: $os (only Darwin/launchd and Linux/systemd are implemented)" ;;
    esac
}

autoindex_macos() {
    local interval="$1" label="$2"
    local notmuch_bin la_dir plist_dst
    notmuch_bin="$(command -v notmuch)"
    la_dir="$HOME/Library/LaunchAgents"
    plist_dst="$la_dir/$label.plist"

    echo "[autoindex] macOS: LaunchAgent $label, interval ${interval}s -> $plist_dst"
    run mkdir -p "$la_dir"

    render() {
        cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$notmuch_bin</string>
        <string>new</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$interval</integer>
</dict>
</plist>
PLIST
    }

    if [ "$DRY_RUN" = 1 ]; then
        echo "  + render + plutil -lint + write $plist_dst"
        echo "  --- rendered plist ---"
        render | sed 's/^/  | /'
        echo "  + launchctl bootout gui/\$(id -u)/$label"
        echo "  + launchctl bootstrap gui/\$(id -u) $plist_dst"
        echo "  + launchctl kickstart -k gui/\$(id -u)/$label"
        return 0
    fi

    local tmp_plist
    tmp_plist="$(mktemp)"
    render > "$tmp_plist"
    plutil -lint "$tmp_plist" >/dev/null || { rm -f "$tmp_plist"; die "autoindex: rendered plist failed plutil -lint"; }
    mv "$tmp_plist" "$plist_dst"

    local domain
    domain="gui/$(id -u)"
    launchctl bootout "$domain/$label" 2>/dev/null || true
    launchctl bootstrap "$domain" "$plist_dst"
    launchctl kickstart -k "$domain/$label"
    echo "[autoindex] done. Verify: launchctl list | grep '$label'"
}

autoindex_linux() {
    local interval="$1" label="$2"
    local notmuch_bin unit_dir service_dst timer_dst
    notmuch_bin="$(command -v notmuch)"
    unit_dir="$HOME/.config/systemd/user"
    service_dst="$unit_dir/$label.service"
    timer_dst="$unit_dir/$label.timer"

    echo "[autoindex] Linux: systemd --user timer $label, interval ${interval}s -> $timer_dst"
    run mkdir -p "$unit_dir"

    render_service() {
        cat <<UNIT
[Unit]
Description=mailbox-memory: notmuch new (auto-index)

[Service]
Type=oneshot
ExecStart=$notmuch_bin new
UNIT
    }
    render_timer() {
        cat <<UNIT
[Unit]
Description=mailbox-memory: run notmuch new every ${interval}s

[Timer]
OnBootSec=${interval}
OnUnitActiveSec=${interval}

[Install]
WantedBy=timers.target
UNIT
    }

    if [ "$DRY_RUN" = 1 ]; then
        echo "  + write $service_dst"
        render_service | sed 's/^/  | /'
        echo "  + write $timer_dst"
        render_timer | sed 's/^/  | /'
        echo "  + systemctl --user daemon-reload"
        echo "  + systemctl --user enable --now $label.timer"
        return 0
    fi

    render_service > "$service_dst"
    render_timer > "$timer_dst"
    systemctl --user daemon-reload
    systemctl --user enable --now "$label.timer"
    echo "[autoindex] done. Verify: systemctl --user status $label.timer"
}

# ----------------------------------------------------------------------------
# postfix — OPT-IN Tier 2. Generalized, sanitized descendant of
# ~/.mail/.postfix/vmailbox-gen (operator-machine-only source — design §2/§4).
#
# NOT required for the "mail yourself a memory" demo (Tier 1 above). This is
# cross-host / multi-agent mail. Documented up front, not silently magic:
# it is macOS + postfix -shaped (the map lives under /etc/postfix/agents.d,
# owned admin:_postfix 2750, because virtual(8) runs as _postfix and cannot
# traverse a 0750 home dir) — on Linux, adapt the map path and the
# postfix-user/group names for your distro's postfix package; the
# generate/sanitize/atomic-write logic below is itself portable.
# ----------------------------------------------------------------------------
cmd_postfix() {
    local host="" root="${MAILBOX_MEMORY_ROOT:-$HOME/.mail}" out="" print=0 no_postmap=0
    local magicdns="${MAGICDNS_SUFFIX:-example.ts.net}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --host)              host="${2:?--host needs a value}"; shift 2 ;;
            --root)              root="${2:?--root needs a value}"; shift 2 ;;
            --out)               out="${2:?--out needs a value}"; shift 2 ;;
            --magicdns-suffix)   magicdns="${2:?--magicdns-suffix needs a value}"; shift 2 ;;
            --print)             print=1; shift ;;
            --no-postmap)        no_postmap=1; shift ;;
            --dry-run)           DRY_RUN=1; shift ;;
            -h|--help)           usage; exit 0 ;;
            *)                   die "postfix: unknown argument: $1 (try --help)" ;;
        esac
    done

    [ -n "$host" ] || host="$(hostname -s)"
    local fqdn="$host.$magicdns"
    local agents_dir="$root/agents"
    local target="${out:-/etc/postfix/agents.d/vmailbox}"
    local state_dir
    state_dir="$(dirname "$target")"

    echo "[postfix] Tier 2 (opt-in): agents.d prerequisite — $state_dir must already"
    echo "[postfix] exist, mode 2750, owner:group admin:_postfix (macOS). Not created"
    echo "[postfix] here (system-level, needs root once) — see references/mail-troubleshooting.md."
    echo "[postfix] host: $host  fqdn: $fqdn  agents: $agents_dir  target: $target"

    # sanitize NAME — fold to lowercase, keep only [a-z0-9_.-]; matches
    # postfix's own key folding. A name that sanitizes to empty is skipped.
    sanitize() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-'; }

    # generate — sorted + de-duplicated map body: deterministic, two runs
    # over the same tree produce a byte-identical map.
    generate() {
        local dir name san
        [ -d "$agents_dir" ] || return 0
        for dir in "$agents_dir"/*/; do
            [ -d "$dir" ] || continue
            name="$(basename "$dir")"
            case "$name" in .*) continue ;; esac
            san="$(sanitize "$name")"
            [ -n "$san" ] || continue
            case "$san" in .|..) continue ;; esac
            printf '%s@%s\tagents/%s/\n' "$san" "$host" "$san"
            printf '%s@%s\tagents/%s/\n' "$san" "$fqdn" "$san"
        done | LC_ALL=C sort -u
    }

    if [ "$print" = 1 ] || [ "$DRY_RUN" = 1 ]; then
        generate
        if [ "$DRY_RUN" = 1 ]; then
            # no_postmap is always SET (0 or 1), so ${no_postmap:+...} (a
            # set-ness test) would always expand — gate on the VALUE instead
            # (foreman review nit).
            local skip_msg=""
            [ "$no_postmap" = 1 ] && skip_msg=" (skipping postmap)"
            echo "  + (dry-run) would write the map above to $target$skip_msg"
        fi
        return 0
    fi

    [ -d "$state_dir" ] || die "postfix: map dir $state_dir does not exist — create it first (2750, admin:_postfix on macOS), see references/mail-troubleshooting.md"

    local tmp
    tmp="$(mktemp "$state_dir/vmailbox.XXXXXX")"
    # `tmp` is `local` to this function, but a trap fires in the SCRIPT's
    # (not the function's) scope — by the time an EXIT trap runs, a local
    # var from an already-returned function is unset, and "$tmp" would trip
    # `set -u` ("unbound variable"), turning a clean run into a false
    # failure (verified live). ${tmp:-} sidesteps that; `trap - EXIT` at the
    # end of the success path removes it before it can ever fire stale.
    # shellcheck disable=SC2064
    trap 'rm -f "${tmp:-}" "${tmp:-}.db" 2>/dev/null || true' EXIT
    generate > "$tmp"
    chmod 0640 "$tmp"

    if [ "$no_postmap" = 0 ]; then
        command -v postmap >/dev/null 2>&1 || die "postfix: postmap not on PATH — cannot build $target.db"
        postmap "hash:$tmp"
        chmod 0640 "$tmp.db"
        mv -f "$tmp" "$target"
        mv -f "$tmp.db" "$target.db"
    else
        mv -f "$tmp" "$target"
    fi
    trap - EXIT

    printf '[postfix] wrote %s (%d entries) for host %s\n' \
        "$target" "$(wc -l < "$target" | tr -d ' ')" "$host"
}

# ----------------------------------------------------------------------------
# all — maildir + notmuch + autoindex. NEVER postfix (opt-in only, by name).
# ----------------------------------------------------------------------------
cmd_all() {
    local extra=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; extra+=(--dry-run); shift ;;
            -h|--help) usage; exit 0 ;;
            *)         die "all: unknown argument: $1 (try --help)" ;;
        esac
    done
    # extra is empty unless --dry-run was passed. Under `set -u`, "${extra[@]}"
    # on an EMPTY array is an "unbound variable" error on bash <= 3.2 (macOS's
    # stock /bin/bash, verified live on 3.2.57) — the ${extra[@]+"${extra[@]}"}
    # idiom sidesteps it: expands to nothing when unset/empty, to the array
    # otherwise. `setup.sh all` (no --dry-run) is the flagship quickstart
    # command; it must not crash on a stock Mac (foreman review, BLOCKER).
    cmd_maildir "${extra[@]+"${extra[@]}"}"
    echo
    cmd_notmuch "${extra[@]+"${extra[@]}"}"
    echo
    cmd_autoindex "${extra[@]+"${extra[@]}"}"
}

# ----------------------------------------------------------------------------
# dispatch
# ----------------------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 1; }

sub="$1"; shift
case "$sub" in
    maildir)    cmd_maildir "$@" ;;
    notmuch)    cmd_notmuch "$@" ;;
    autoindex)  cmd_autoindex "$@" ;;
    postfix)    cmd_postfix "$@" ;;
    all)        cmd_all "$@" ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown subcommand: $sub (try --help)" ;;
esac
