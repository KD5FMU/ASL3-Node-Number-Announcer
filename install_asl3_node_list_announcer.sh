#!/usr/bin/env bash
# ASL3 Node List Announcer - single-file installer
# Concept and testing: Freddie Mac, KD5FMU - Ham Radio Crusader
set -Eeuo pipefail

PROGRAM_NAME="ASL3 Node List Announcer"
VERSION="0.3.0"
DEFAULT_DTMF="698"
DEFAULT_SILENCE_SECONDS="2.0"
DTMF_CODE="$DEFAULT_DTMF"
SILENCE_SECONDS="$DEFAULT_SILENCE_SECONDS"
SILENCE_EXPLICIT=0
VOICE=""
AUTO_UPDATE=1
MODE="install"

RPT_CONF="/etc/asterisk/rpt.conf"
CUSTOM_RPT_DIR="/etc/asterisk/custom/rpt"
CUSTOM_RPT_FILE="$CUSTOM_RPT_DIR/node-list-announcer.conf"
LOCAL_CONFIG_DIR="/etc/asterisk/local"
LOCAL_CONFIG="$LOCAL_CONFIG_DIR/node-list-announce.ini"
UPDATE_SCRIPT="/usr/local/sbin/asl3-node-list-update"
UNINSTALL_SCRIPT="/usr/local/sbin/asl3-node-list-uninstall"
SOUND_DIR="/usr/share/asterisk/sounds/custom/asl3-node-list"
LEGACY_SOUND_DIR="/usr/local/share/asterisk/sounds/custom/asl3-node-list"
SERVICE_FILE="/etc/systemd/system/asl3-node-list-update.service"
PATH_FILE="/etc/systemd/system/asl3-node-list-update.path"
INCLUDE_MARKER="; ASL3 Node List Announcer custom include"
INCLUDE_LINE='#tryinclude "custom/rpt/*.conf"'
BACKUP_DIR="/var/backups/asl3-node-list-announcer"

usage() {
    cat <<EOF
$PROGRAM_NAME single-file installer v$VERSION

Usage:
  sudo $0 [options]
  sudo $0 --uninstall

Options:
  --dtmf CODE       DTMF digits after * (default: $DEFAULT_DTMF)
  --voice NAME      Optional installed asl-tts/Piper voice filename
  --silence SEC     Lead-in silence before speech (default: $DEFAULT_SILENCE_SECONDS)
  --no-auto-update  Do not enable the systemd configuration watcher
  --uninstall       Remove the Node List Announcer
  -h, --help        Show this help

Examples:
  sudo $0
  sudo $0 --dtmf 698
  sudo $0 --silence 2.5
  sudo $0 --voice en_US-lessac-low.onnx
  sudo $0 --uninstall
EOF
}

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

backup_file() {
    local source="$1"
    [[ -e "$source" ]] || return 0
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -a "$source" "$BACKUP_DIR/$(basename "$source").$stamp.bak"
}

remove_managed_include() {
    [[ -f "$RPT_CONF" ]] || return 0
    grep -Fqx "$INCLUDE_MARKER" "$RPT_CONF" || return 0

    backup_file "$RPT_CONF"
    python3 - "$RPT_CONF" "$INCLUDE_MARKER" "$INCLUDE_LINE" <<'PY_REMOVE_INCLUDE'
import sys
from pathlib import Path

path = Path(sys.argv[1])
marker = sys.argv[2]
include_line = sys.argv[3]
lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
out = []
skip_expected_include = False
for line in lines:
    if line == marker:
        skip_expected_include = True
        continue
    if skip_expected_include and line == include_line:
        skip_expected_include = False
        continue
    skip_expected_include = False
    out.append(line)
path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY_REMOVE_INCLUDE
}

perform_uninstall() {
    [[ $EUID -eq 0 ]] || die "Run the uninstaller as root."

    log "Disabling the automatic update watcher."
    systemctl disable --now asl3-node-list-update.path >/dev/null 2>&1 || true

    rm -f "$PATH_FILE" "$SERVICE_FILE"
    systemctl daemon-reload

    rm -f "$CUSTOM_RPT_FILE" "$UPDATE_SCRIPT"
    rm -rf "$SOUND_DIR" "$LEGACY_SOUND_DIR"
    rm -f "$LOCAL_CONFIG"
    remove_managed_include

    if systemctl list-unit-files asterisk.service >/dev/null 2>&1; then
        log "Restarting Asterisk."
        systemctl restart asterisk.service
    fi

    # Remove this last so the installed uninstaller may delete itself safely.
    rm -f "$UNINSTALL_SCRIPT"

    cat <<'EOF'

ASL3 Node List Announcer has been removed.
The official asl3-tts package was left installed because other ASL3 features may use it.
Backups remain in /var/backups/asl3-node-list-announcer/.
EOF
}

while (($#)); do
    case "$1" in
        --dtmf)
            (($# >= 2)) || die "--dtmf requires a value"
            DTMF_CODE="$2"
            shift 2
            ;;
        --voice)
            (($# >= 2)) || die "--voice requires a value"
            VOICE="$2"
            shift 2
            ;;
        --silence)
            (($# >= 2)) || die "--silence requires a value"
            SILENCE_SECONDS="$2"
            SILENCE_EXPLICIT=1
            shift 2
            ;;
        --no-auto-update)
            AUTO_UPDATE=0
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [[ "$MODE" == "uninstall" ]]; then
    perform_uninstall
    exit 0
fi

[[ $EUID -eq 0 ]] || die "Run this installer as root: sudo $0"
[[ "$DTMF_CODE" =~ ^[0-9A-Da-d]{2,12}$ ]] || die "DTMF code must contain 2-12 digits/A-D characters, without the leading *."
[[ "$VOICE" != *$'\n'* && "$VOICE" != *$'\r'* ]] || die "Voice name contains invalid characters."
DTMF_CODE="${DTMF_CODE^^}"

[[ -f "$RPT_CONF" ]] || die "$RPT_CONF was not found. This installer is intended for AllStarLink 3."
command -v asterisk >/dev/null 2>&1 || die "The asterisk command was not found."
command -v systemctl >/dev/null 2>&1 || die "The systemctl command was not found."
id asterisk >/dev/null 2>&1 || die "The asterisk user was not found."

if ! command -v python3 >/dev/null 2>&1; then
    log "Installing Python 3."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3
fi

python3 - "$SILENCE_SECONDS" <<'PY_VALIDATE_SILENCE' || die "Silence must be a number from 0 through 10 seconds."
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if 0 <= value <= 10 else 1)
PY_VALIDATE_SILENCE

if ! command -v asl-tts >/dev/null 2>&1; then
    log "asl-tts is not installed; installing the official asl3-tts package."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y asl3-tts
fi

command -v runuser >/dev/null 2>&1 || die "The runuser command was not found. Install the util-linux package."

mkdir -p "$BACKUP_DIR" "$CUSTOM_RPT_DIR" "$LOCAL_CONFIG_DIR" "$SOUND_DIR"
chmod 755 "$CUSTOM_RPT_DIR" "$LOCAL_CONFIG_DIR"
chown asterisk:asterisk "$SOUND_DIR"
chmod 775 "$SOUND_DIR"

if ! grep -Eq '^[[:space:]]*#(try)?include[[:space:]]+["<]?custom/rpt/\*\.conf[">]?' "$RPT_CONF"; then
    log "Adding the ASL3 custom rpt include to rpt.conf."
    backup_file "$RPT_CONF"
    {
        printf '\n%s\n' "$INCLUDE_MARKER"
        printf '%s\n' "$INCLUDE_LINE"
    } >> "$RPT_CONF"
fi

log "Installing the embedded announcement builder."
cat > "$UPDATE_SCRIPT" <<'PY_NODE_LIST_UPDATE'
#!/usr/bin/env python3
"""Build the spoken ASL3 local-node announcement using asl-tts."""

from __future__ import annotations

import argparse
import configparser
import glob
import logging
import os
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable

PROGRAM = "asl3-node-list-update"
VERSION = "0.3.0"

RPT_CONF = Path(os.environ.get("ASL3_NODE_LIST_RPT_CONF", "/etc/asterisk/rpt.conf"))
CONFIG_FILE = Path(
    os.environ.get(
        "ASL3_NODE_LIST_CONFIG", "/etc/asterisk/local/node-list-announce.ini"
    )
)
SOUND_BASE = Path(
    os.environ.get(
        "ASL3_NODE_LIST_SOUND_BASE",
        "/usr/share/asterisk/sounds/custom/asl3-node-list/node-list",
    )
)

SECTION_RE = re.compile(r"^\s*\[([^\]]+)\](?:\([^\)]*\))?\s*(?:;.*)?$")
INCLUDE_RE = re.compile(r'^\s*#(?:try)?include\s+["<]?([^">;]+)[">]?\s*(?:;.*)?$', re.I)
NUMERIC_NODE_RE = re.compile(r"^[0-9]{3,10}$")

DIGIT_WORDS = {
    "0": "zero",
    "1": "one",
    "2": "two",
    "3": "three",
    "4": "four",
    "5": "five",
    "6": "six",
    "7": "seven",
    "8": "eight",
    "9": "nine",
}


def require_root() -> None:
    if os.geteuid() != 0:
        raise PermissionError(f"{PROGRAM} must be run as root. Try: sudo {PROGRAM}")


def strip_inline_comment(value: str) -> str:
    """Remove Asterisk-style trailing comments while preserving ordinary text."""
    for marker in (";", "#"):
        idx = value.find(marker)
        if idx >= 0:
            value = value[:idx]
    return value.strip().strip('"').strip("'")


def resolve_include(raw_path: str, parent: Path) -> list[Path]:
    raw_path = strip_inline_comment(raw_path)
    candidate = Path(raw_path)
    if not candidate.is_absolute():
        candidate = parent / candidate
    return [Path(p) for p in sorted(glob.glob(str(candidate)))]


def collect_config_files(root: Path) -> list[Path]:
    """Recursively collect rpt.conf and files referenced by #include/#tryinclude."""
    collected: list[Path] = []
    visited: set[Path] = set()

    def walk(path: Path) -> None:
        try:
            canonical = path.resolve(strict=True)
        except FileNotFoundError:
            return
        if canonical in visited or not canonical.is_file():
            return
        visited.add(canonical)
        collected.append(canonical)

        try:
            lines = canonical.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:
            logging.warning("Could not read included file %s: %s", canonical, exc)
            return

        for line in lines:
            match = INCLUDE_RE.match(line)
            if not match:
                continue
            for included in resolve_include(match.group(1), canonical.parent):
                walk(included)

    walk(root)
    return collected


def detect_nodes(files: Iterable[Path]) -> list[str]:
    nodes: set[str] = set()
    for path in files:
        try:
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                match = SECTION_RE.match(line)
                if not match:
                    continue
                section = match.group(1).strip()
                if NUMERIC_NODE_RE.fullmatch(section):
                    nodes.add(section)
        except OSError as exc:
            logging.warning("Could not inspect %s: %s", path, exc)
    return sorted(nodes, key=lambda item: (int(item), item))


def read_settings(path: Path) -> tuple[configparser.ConfigParser, set[str], str, float]:
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str.lower
    if path.exists():
        cfg.read(path, encoding="utf-8")

    if not cfg.has_section("general"):
        cfg.add_section("general")

    excluded_raw = cfg.get("general", "exclude_nodes", fallback="")
    excluded = {
        token.strip()
        for token in re.split(r"[,\s]+", excluded_raw)
        if token.strip()
    }
    voice = cfg.get("general", "voice", fallback="").strip()
    raw_silence = cfg.get("general", "lead_silence_seconds", fallback="2.0").strip()
    try:
        silence_seconds = float(raw_silence)
    except ValueError as exc:
        raise RuntimeError(
            f"lead_silence_seconds must be numeric, not {raw_silence!r}"
        ) from exc
    if not 0 <= silence_seconds <= 10:
        raise RuntimeError("lead_silence_seconds must be between 0 and 10")
    return cfg, excluded, voice, silence_seconds


def spoken_digits(node: str) -> str:
    return " ".join(DIGIT_WORDS[digit] for digit in node)


def friendly_name(cfg: configparser.ConfigParser, node: str) -> str:
    if not cfg.has_section(node):
        return ""
    return cfg.get(node, "name", fallback="").strip()


def natural_join(items: list[str]) -> str:
    if not items:
        return ""
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]}, and {items[1]}"
    return f"{', '.join(items[:-1])}, and {items[-1]}"


def build_message(nodes: list[str], cfg: configparser.ConfigParser) -> str:
    custom_intro = cfg.get("general", "intro", fallback="").strip()
    if custom_intro:
        intro = custom_intro.rstrip(" .")
    elif len(nodes) == 1:
        intro = "This All Star Link server is configured for one node"
    else:
        intro = f"This All Star Link server is configured for {len(nodes)} nodes"

    entries: list[str] = []
    for node in nodes:
        name = friendly_name(cfg, node)
        digits = spoken_digits(node)
        if name:
            entries.append(f"{name}, node {digits}")
        else:
            entries.append(f"node {digits}")

    return f"{intro}. The configured node {'is' if len(nodes) == 1 else 'numbers are'}, {natural_join(entries)}."


def find_command(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise FileNotFoundError(f"Required command not found: {name}")
    return path


def run_tts(
    node: str, message: str, voice: str, output_base: Path, silence_seconds: float
) -> Path:
    asl_tts = find_command("asl-tts")
    runuser = find_command("runuser")

    output_base.parent.mkdir(parents=True, exist_ok=True)
    try:
        asterisk = pwd.getpwnam("asterisk")
    except KeyError as exc:
        raise RuntimeError("The asterisk user does not exist on this system") from exc

    os.chown(output_base.parent, asterisk.pw_uid, asterisk.pw_gid)
    os.chmod(output_base.parent, 0o775)

    with tempfile.NamedTemporaryFile(
        prefix=".node-list-", dir=output_base.parent, delete=True
    ) as tmp:
        temporary_base = Path(tmp.name)
    temporary_ul = Path(f"{temporary_base}.ul")

    command = [
        runuser,
        "-u",
        "asterisk",
        "--",
        asl_tts,
        "-n",
        node,
        "-t",
        message,
        "-f",
        str(temporary_base),
    ]
    if voice:
        command.extend(["-v", voice])

    logging.info("Generating announcement with asl-tts for node %s", node)
    try:
        subprocess.run(command, check=True)
        if not temporary_ul.exists() or temporary_ul.stat().st_size == 0:
            raise RuntimeError(f"asl-tts did not create a valid file: {temporary_ul}")

        destination = Path(f"{output_base}.ul")
        padded_ul = Path(f"{temporary_base}.padded.ul")

        # Raw Asterisk .ul audio is 8 kHz, 8-bit mu-law. Byte 0xFF is silence.
        silence_bytes = round(silence_seconds * 8000)
        with temporary_ul.open("rb") as source, padded_ul.open("wb") as target:
            if silence_bytes:
                target.write(b"\xff" * silence_bytes)
            shutil.copyfileobj(source, target)

        padded_ul.chmod(0o644)
        os.chown(padded_ul, asterisk.pw_uid, asterisk.pw_gid)
        os.replace(padded_ul, destination)
        return destination
    finally:
        temporary_ul.unlink(missing_ok=True)
        Path(f"{temporary_base}.padded.ul").unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect configured ASL3 nodes and build a spoken node-list announcement."
    )
    parser.add_argument("--dry-run", action="store_true", help="print the detected nodes and message without generating audio")
    parser.add_argument("--print-message", action="store_true", help="print the generated announcement text")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    parser.add_argument("--verbose", action="store_true", help="enable detailed logging")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    try:
        if not RPT_CONF.is_file():
            raise FileNotFoundError(f"ASL3 configuration not found: {RPT_CONF}")

        config_files = collect_config_files(RPT_CONF)
        logging.debug("Inspected files: %s", ", ".join(str(p) for p in config_files))
        nodes = detect_nodes(config_files)
        cfg, excluded, voice, silence_seconds = read_settings(CONFIG_FILE)
        nodes = [node for node in nodes if node not in excluded]

        if not nodes:
            raise RuntimeError(
                "No numeric ASL3 node sections were found after applying exclude_nodes"
            )

        message = build_message(nodes, cfg)
        print(f"Detected nodes: {', '.join(nodes)}")
        if args.print_message or args.dry_run:
            print(f"Announcement: {message}")
        if args.dry_run:
            return 0

        require_root()
        logging.info("Adding %.2f seconds of lead-in silence", silence_seconds)
        output = run_tts(nodes[0], message, voice, SOUND_BASE, silence_seconds)
        print(f"Lead-in silence: {silence_seconds:g} seconds")
        print(f"Announcement created: {output}")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        logging.error("%s", exc)
        return 1


if __name__ == "__main__":
    sys.exit(main())

PY_NODE_LIST_UPDATE
chmod 755 "$UPDATE_SCRIPT"
chown root:root "$UPDATE_SCRIPT"

log "Inspecting function stanzas and checking DTMF code *$DTMF_CODE."
ERROR_FILE="$(mktemp)"
set +e
FUNCTION_STANZAS="$({
    RPT_CONF="$RPT_CONF" CUSTOM_RPT_FILE="$CUSTOM_RPT_FILE" DTMF_CODE="$DTMF_CODE" python3 - <<'PY_FUNCTION_SCAN'
from __future__ import annotations

import glob
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

root = Path(os.environ["RPT_CONF"])
our_file = Path(os.environ["CUSTOM_RPT_FILE"])
requested = os.environ["DTMF_CODE"].upper()
section_re = re.compile(
    r"^\s*\[([^\]]+)\](?:\(([^\)]*)\))?\s*(?:;.*)?$"
)
include_re = re.compile(
    r'^\s*#(?:try)?include\s+["<]?([^">;]+)[">]?\s*(?:;.*)?$', re.I
)
assignment_re = re.compile(r"^\s*([^=;#]+?)\s*=\s*(.*?)\s*$")
dtmf_re = re.compile(r"^[0-9A-D]+$", re.I)
visited: set[Path] = set()
files: list[Path] = []


def clean(value: str) -> str:
    for marker in (";", "#"):
        if marker in value:
            value = value.split(marker, 1)[0]
    return value.strip().strip('"').strip("'")


def walk(path: Path) -> None:
    try:
        path = path.resolve(strict=True)
    except FileNotFoundError:
        return
    if path in visited or not path.is_file():
        return
    visited.add(path)
    files.append(path)
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = include_re.match(line)
        if not match:
            continue
        included = Path(clean(match.group(1)))
        if not included.is_absolute():
            included = path.parent / included
        for found in sorted(glob.glob(str(included))):
            walk(Path(found))


walk(root)
our_resolved = our_file.resolve() if our_file.exists() else None
parents: dict[str, set[str]] = defaultdict(set)
active_function_stanzas: set[str] = set()
section_entries: dict[str, list[tuple[Path, int, str, str]]] = defaultdict(list)

for path in files:
    if our_resolved is not None and path == our_resolved:
        continue
    current = ""
    for lineno, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
    ):
        section_match = section_re.match(line)
        if section_match:
            current = section_match.group(1).strip()
            raw_parents = section_match.group(2) or ""
            for parent in (part.strip() for part in raw_parents.split(",")):
                if parent and parent not in {"!", "+"}:
                    parents[current].add(parent)
            continue
        assignment_match = assignment_re.match(line)
        if not assignment_match or not current:
            continue
        key = assignment_match.group(1).strip()
        value = clean(assignment_match.group(2))
        section_entries[current].append((path, lineno, key, line.strip()))
        if key.lower() == "functions" and value:
            active_function_stanzas.add(value)


if not active_function_stanzas:
    active_function_stanzas.add("functions")


def inheritance_closure(sections: set[str]) -> set[str]:
    result = set(sections)
    stack = list(sections)
    while stack:
        section = stack.pop()
        for parent in parents.get(section, set()):
            if parent not in result:
                result.add(parent)
                stack.append(parent)
    return result


scanned_sections = inheritance_closure(active_function_stanzas)
existing: list[tuple[str, Path, int, str, str]] = []
for section in scanned_sections:
    for path, lineno, key, source_line in section_entries.get(section, []):
        code = key.strip().upper()
        if dtmf_re.fullmatch(code):
            existing.append((code, path, lineno, section, source_line))


def collision_reason(candidate: str, existing_code: str) -> str | None:
    if candidate == existing_code:
        return "exact assignment"
    if candidate.startswith(existing_code):
        return f"existing *{existing_code} is a prefix of *{candidate}"
    if existing_code.startswith(candidate):
        return f"requested *{candidate} is a prefix of existing *{existing_code}"
    return None


conflicts: list[str] = []
for existing_code, path, lineno, section, source_line in existing:
    reason = collision_reason(requested, existing_code)
    if reason:
        conflicts.append(
            f"{reason}: {path}:{lineno}: [{section}] {source_line}"
        )


def safe(candidate: str) -> bool:
    return not any(collision_reason(candidate, item[0]) for item in existing)


if conflicts:
    print("DTMF_CONFLICT", file=sys.stderr)
    for conflict in conflicts:
        print(conflict, file=sys.stderr)
    suggestions: list[str] = []
    preferred = ["698", "697", "699", "696", "695", "694", "693", "692", "691", "690"]
    candidates = preferred + [str(number) for number in range(600, 1000)]
    for candidate in candidates:
        if candidate != requested and candidate not in suggestions and safe(candidate):
            suggestions.append(candidate)
        if len(suggestions) == 5:
            break
    if suggestions:
        print("Safe-looking alternatives: " + ", ".join(f"*{item}" for item in suggestions), file=sys.stderr)
    sys.exit(24)

for stanza in sorted(active_function_stanzas):
    print(stanza)
PY_FUNCTION_SCAN
} 2>"$ERROR_FILE")"
STATUS=$?
set -e
if [[ $STATUS -ne 0 ]]; then
    cat "$ERROR_FILE" >&2 || true
    rm -f "$ERROR_FILE"
    if [[ $STATUS -eq 24 ]]; then
        die "DTMF code *$DTMF_CODE conflicts with an existing function or prefix. Choose one of the alternatives shown above."
    fi
    die "Unable to inspect $RPT_CONF."
fi
rm -f "$ERROR_FILE"

[[ -n "$FUNCTION_STANZAS" ]] || FUNCTION_STANZAS="functions"
backup_file "$CUSTOM_RPT_FILE"
{
    cat <<EOF
; $PROGRAM_NAME v$VERSION
; Managed by the single-file installer.
; Enter *$DTMF_CODE from the local receiver to hear the configured node list.

EOF
    while IFS= read -r stanza; do
        [[ -n "$stanza" ]] || continue
        printf '[%s](+)\n' "$stanza"
        printf '%s = localplay,%s/node-list\n\n' "$DTMF_CODE" "$SOUND_DIR"
    done <<< "$FUNCTION_STANZAS"
} > "$CUSTOM_RPT_FILE"
chown root:asterisk "$CUSTOM_RPT_FILE"
chmod 640 "$CUSTOM_RPT_FILE"

if [[ ! -f "$LOCAL_CONFIG" ]]; then
    cat > "$LOCAL_CONFIG" <<EOF
[general]
; Optional installed Piper/asl-tts voice filename.
; Leave blank to use the ASL3 default voice.
voice = $VOICE

; Silence before speech, allowing a receiving radio time to open squelch.
lead_silence_seconds = $SILENCE_SECONDS

; Comma- or space-separated node numbers that should not be announced.
exclude_nodes =

; Optional custom opening sentence. Leave blank for automatic wording.
intro =

; Optional friendly names may be added as shown below.
; [577881]
; name = Ham Shack Node
EOF
else
    backup_file "$LOCAL_CONFIG"
    python3 - "$LOCAL_CONFIG" "$VOICE" "$SILENCE_SECONDS" "$SILENCE_EXPLICIT" <<'PY_UPDATE_CONFIG'
import configparser
import sys
from pathlib import Path

path = Path(sys.argv[1])
voice = sys.argv[2]
silence = sys.argv[3]
silence_explicit = sys.argv[4] == "1"
cfg = configparser.ConfigParser(interpolation=None)
cfg.read(path, encoding="utf-8")
if not cfg.has_section("general"):
    cfg.add_section("general")
if voice:
    cfg.set("general", "voice", voice)
if silence_explicit or not cfg.has_option("general", "lead_silence_seconds"):
    cfg.set("general", "lead_silence_seconds", silence)
for key in ("exclude_nodes", "intro"):
    if not cfg.has_option("general", key):
        cfg.set("general", key, "")
with path.open("w", encoding="utf-8") as handle:
    cfg.write(handle)
PY_UPDATE_CONFIG
fi
chown root:asterisk "$LOCAL_CONFIG"
chmod 640 "$LOCAL_CONFIG"

CONFIGURED_SILENCE="$(python3 - "$LOCAL_CONFIG" <<'PY_READ_SILENCE'
import configparser
import sys
cfg = configparser.ConfigParser(interpolation=None)
cfg.read(sys.argv[1], encoding="utf-8")
print(cfg.get("general", "lead_silence_seconds", fallback="2.0"))
PY_READ_SILENCE
)"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Build the ASL3 spoken local-node list
After=asterisk.service
ConditionPathExists=$RPT_CONF

[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
User=root
Group=root
EOF

cat > "$PATH_FILE" <<EOF
[Unit]
Description=Watch ASL3 configuration for node-list changes

[Path]
PathChanged=$RPT_CONF
PathChanged=$CUSTOM_RPT_DIR
PathChanged=$LOCAL_CONFIG
Unit=asl3-node-list-update.service

[Install]
WantedBy=multi-user.target
EOF

cat > "$UNINSTALL_SCRIPT" <<'PY_UNINSTALLER'
#!/usr/bin/env bash
set -Eeuo pipefail

RPT_CONF="/etc/asterisk/rpt.conf"
CUSTOM_RPT_FILE="/etc/asterisk/custom/rpt/node-list-announcer.conf"
LOCAL_CONFIG="/etc/asterisk/local/node-list-announce.ini"
UPDATE_SCRIPT="/usr/local/sbin/asl3-node-list-update"
UNINSTALL_SCRIPT="/usr/local/sbin/asl3-node-list-uninstall"
SOUND_DIR="/usr/share/asterisk/sounds/custom/asl3-node-list"
LEGACY_SOUND_DIR="/usr/local/share/asterisk/sounds/custom/asl3-node-list"
SERVICE_FILE="/etc/systemd/system/asl3-node-list-update.service"
PATH_FILE="/etc/systemd/system/asl3-node-list-update.path"
INCLUDE_MARKER="; ASL3 Node List Announcer custom include"
INCLUDE_LINE='#tryinclude "custom/rpt/*.conf"'
BACKUP_DIR="/var/backups/asl3-node-list-announcer"

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root: sudo asl3-node-list-uninstall"
mkdir -p "$BACKUP_DIR"

systemctl disable --now asl3-node-list-update.path >/dev/null 2>&1 || true
rm -f "$PATH_FILE" "$SERVICE_FILE"
systemctl daemon-reload
rm -f "$CUSTOM_RPT_FILE" "$UPDATE_SCRIPT"
rm -rf "$SOUND_DIR" "$LEGACY_SOUND_DIR"
rm -f "$LOCAL_CONFIG"

if [[ -f "$RPT_CONF" ]] && grep -Fqx "$INCLUDE_MARKER" "$RPT_CONF"; then
    cp -a "$RPT_CONF" "$BACKUP_DIR/rpt.conf.uninstall.$(date +%Y%m%d-%H%M%S).bak"
    python3 - "$RPT_CONF" "$INCLUDE_MARKER" "$INCLUDE_LINE" <<'PY_REMOVE'
import sys
from pathlib import Path
path = Path(sys.argv[1])
marker = sys.argv[2]
include_line = sys.argv[3]
lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
out = []
skip = False
for line in lines:
    if line == marker:
        skip = True
        continue
    if skip and line == include_line:
        skip = False
        continue
    skip = False
    out.append(line)
path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY_REMOVE
fi

if systemctl list-unit-files asterisk.service >/dev/null 2>&1; then
    log "Restarting Asterisk."
    systemctl restart asterisk.service
fi

rm -f "$UNINSTALL_SCRIPT"
printf '\nASL3 Node List Announcer has been removed.\n'
printf 'The asl3-tts package and backup files were left in place.\n'
PY_UNINSTALLER
chmod 755 "$UNINSTALL_SCRIPT"
chown root:root "$UNINSTALL_SCRIPT"

systemctl daemon-reload

log "Generating the spoken announcement."
"$UPDATE_SCRIPT" --print-message

if [[ -d "$LEGACY_SOUND_DIR" && "$LEGACY_SOUND_DIR" != "$SOUND_DIR" ]]; then
    log "Removing the obsolete v0.2.0 sound directory."
    rm -rf "$LEGACY_SOUND_DIR"
fi

runuser -u asterisk -- test -r "$SOUND_DIR/node-list.ul" \
    || die "Asterisk cannot read $SOUND_DIR/node-list.ul."

log "Restarting Asterisk so app_rpt reads the DTMF command."
systemctl restart asterisk.service

if [[ $AUTO_UPDATE -eq 1 ]]; then
    systemctl enable --now asl3-node-list-update.path
else
    systemctl disable --now asl3-node-list-update.path >/dev/null 2>&1 || true
fi

cat <<EOF

============================================================
$PROGRAM_NAME installed successfully
============================================================
Version:            $VERSION
DTMF command:       *$DTMF_CODE
Lead-in silence:    $CONFIGURED_SILENCE seconds
Update command:     sudo asl3-node-list-update --print-message
Configuration:      $LOCAL_CONFIG
app_rpt addition:   $CUSTOM_RPT_FILE
Announcement file: $SOUND_DIR/node-list.ul
Uninstall command:  sudo asl3-node-list-uninstall
Automatic updates: $([[ $AUTO_UPDATE -eq 1 ]] && echo enabled || echo disabled)

Key your local node and enter *$DTMF_CODE to hear the node list.
EOF
