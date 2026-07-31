# UNTESTED

# ASL3 Node List Announcer

**Version 0.2.0 — single-file test release**

ASL3 Node List Announcer lets an operator enter a DTMF command and hear the numeric nodes configured on the local AllStarLink 3 server. The default radio command is **`*997`**.

The project uses one self-contained installer. The installer embeds and creates all supporting scripts, configuration files, systemd units, and the uninstaller.

## Example announcement

> This All Star Link server is configured for three nodes. The configured node numbers are, node five seven seven eight eight one, node five seven seven eight eight four, and node five seven seven eight eight five.

Node numbers are spoken digit-by-digit so the TTS engine does not pronounce them as large cardinal numbers.

## Installation

Clone or download this repository on the ASL3 computer, then run:

```bash
chmod +x install_asl3_node_list_announcer.sh
sudo ./install_asl3_node_list_announcer.sh
```

The default DTMF command is:

```text
*997
```

Do not include the leading `*` when selecting a different installer code:

```bash
sudo ./install_asl3_node_list_announcer.sh --dtmf 998
```

That creates radio command `*998`.

## Installer options

```text
--dtmf CODE       DTMF digits after *
--voice NAME      Optional installed Piper voice filename
--no-auto-update  Do not enable the systemd configuration watcher
--uninstall       Remove the Node List Announcer
-h, --help        Show installer help
```

Example with a different installed Piper voice:

```bash
sudo ./install_asl3_node_list_announcer.sh \
  --voice en_US-lessac-low.onnx
```

## What the installer creates

- `/usr/local/sbin/asl3-node-list-update`
- `/usr/local/sbin/asl3-node-list-uninstall`
- `/etc/asterisk/local/node-list-announce.ini`
- `/etc/asterisk/custom/rpt/node-list-announcer.conf`
- `/usr/local/share/asterisk/sounds/custom/asl3-node-list/node-list.ul`
- `/etc/systemd/system/asl3-node-list-update.service`
- `/etc/systemd/system/asl3-node-list-update.path`

Backups are stored under:

```text
/var/backups/asl3-node-list-announcer/
```

## Friendly node names

Edit:

```text
/etc/asterisk/local/node-list-announce.ini
```

Example:

```ini
[general]
voice =
exclude_nodes = 1999
intro =

[577881]
name = Ham Shack Node

[577884]
name = Workshop Node
```

The systemd watcher will rebuild the audio after this file changes. It can also be rebuilt manually:

```bash
sudo asl3-node-list-update --print-message
```

Preview the detected nodes and wording without creating audio:

```bash
sudo asl3-node-list-update --dry-run --verbose
```

## Uninstallation

After installation, run:

```bash
sudo asl3-node-list-uninstall
```

The original installer can also remove the project:

```bash
sudo ./install_asl3_node_list_announcer.sh --uninstall
```

The uninstaller intentionally leaves the official `asl3-tts` package installed because other ASL3 features may use it.

## Important test-release note

This release has passed syntax checks and simulated configuration tests, but it has not yet been exercised on every ASL3 installation or radio interface. Test it first on a noncritical node and keep the automatically created backups.

## Project credit

Concept and testing: **Freddie Mac, KD5FMU — Ham Radio Crusader**

Initial implementation assistance: OpenAI ChatGPT

## References

- AllStarLink ASL Text-to-Speech: https://allstarlink.github.io/adv-topics/tts/
- AllStarLink Asterisk templates: https://allstarlink.github.io/adv-topics/conftmpl/
- AllStarLink app_rpt source: https://github.com/AllStarLink/app_rpt
