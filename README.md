![logo](https://github.com/KD5FMU/ASL3-Node-Number-Announcer/blob/main/node_announce.png)
# ASL3 Node List Announcer

**Version 1.0.0**

ASL3 Node List Announcer creates a spoken report of the numeric AllStarLink nodes configured on a local ASL3 server. The report is generated with the official `asl-tts` utility and can be requested from the local radio using a DTMF command.

The default command is:

```text
*698
```

The generated announcement begins with **two seconds of silence**. This gives the receiving radio time to open its squelch before the spoken report begins.

## Version 1.0.0 improvements

- Changes the default DTMF command from `*997` to the live-tested `*698`.
- Detects exact DTMF conflicts.
- Detects shorter-prefix conflicts, such as an existing `*99` conflicting with a requested `*997`.
- Detects longer-prefix conflicts, such as a requested `*69` conflicting with an existing `*698`.
- Inspects inherited function templates such as `[functions-main]`, not only the visible `[functions]` stanza.
- Adds a configurable lead-in silence before the announcement.
- Uses the working ASL3 sound location:

```text
/usr/share/asterisk/sounds/custom/asl3-node-list/node-list.ul
```

- Automatically rebuilds the announcement when the ASL3 configuration changes.
- Includes an installed uninstaller.

## Requirements

- AllStarLink 3
- Debian-based ASL3 installation
- Root or `sudo` access
- A working Asterisk/app_rpt installation
- Internet access during installation only if the official `asl3-tts` package is not already installed

The installer installs `python3` and `asl3-tts` through APT when they are missing.

## Installation
You can download it manually
```
sudo wget https://raw.githubusercontent.com/KD5FMU/ASL3-Node-Number-Announcer/refs/heads/main/install_asl3_node_list_announcer.sh
```
or

Download or clone the repository, then run:

```bash
chmod +x install_asl3_node_list_announcer.sh
sudo ./install_asl3_node_list_announcer.sh
```

The installer will:

1. Inspect `/etc/asterisk/rpt.conf` and recursively inspect its included files.
2. Detect locally configured numeric node sections.
3. Inspect the function stanza used by each node.
4. Follow inherited function templates when checking DTMF conflicts.
5. Add the selected DTMF command through a custom ASL3 include file.
6. Generate the spoken node-list announcement.
7. Add the configured lead-in silence.
8. Restart Asterisk so app_rpt loads the new command.
9. Enable the automatic configuration watcher unless disabled by an option.

After installation, key the local node and enter:

```text
*698
```

## Installer options

Show the available options:

```bash
./install_asl3_node_list_announcer.sh --help
```

### Choose another DTMF command

Enter the digits without the leading `*`:

```bash
sudo ./install_asl3_node_list_announcer.sh --dtmf 697
```

The installer checks the proposed command against exact assignments and conflicting prefixes. When a conflict is found, installation stops and several safe-looking alternatives are displayed.

### Change the silence duration

The default is two seconds:

```bash
sudo ./install_asl3_node_list_announcer.sh --silence 2.0
```

A value from `0` through `10` seconds may be used. For example:

```bash
sudo ./install_asl3_node_list_announcer.sh --silence 2.5
```

### Choose another installed voice

```bash
sudo ./install_asl3_node_list_announcer.sh \
  --voice en_US-lessac-low.onnx
```

Leave the voice unset to use the ASL3 default.

### Disable automatic rebuilding

```bash
sudo ./install_asl3_node_list_announcer.sh --no-auto-update
```

The announcement can still be rebuilt manually.

## Configuration

The editable configuration file is:

```text
/etc/asterisk/local/node-list-announce.ini
```

A typical configuration looks like:

```ini
[general]
voice =
lead_silence_seconds = 2.0
exclude_nodes =
intro =

[576336]
name = Ham Radio Crusader Node
```

### Friendly node names

Add a section matching the node number:

```ini
[576336]
name = Ham Radio Crusader Node
```

The announcement will speak the friendly name followed by the node number.

### Exclude private or helper nodes

Use a comma- or space-separated list:

```ini
[general]
exclude_nodes = 1888, 1999
```

### Custom opening sentence

```ini
[general]
intro = This Ham Radio Crusader server currently hosts the following nodes
```

Do not add the final period; the announcement builder adds punctuation.

### Change the silence after installation

Edit:

```ini
lead_silence_seconds = 2.0
```

Then rebuild:

```bash
sudo asl3-node-list-update --print-message
```

## Useful commands

Preview the detected nodes and sentence without generating audio:

```bash
sudo asl3-node-list-update --dry-run --verbose
```

Rebuild the announcement and print the sentence:

```bash
sudo asl3-node-list-update --print-message
```

Show the updater version:

```bash
asl3-node-list-update --version
```

Test the generated audio directly on node 576336:

```bash
sudo asterisk -rx \
  "rpt playback 576336 /usr/share/asterisk/sounds/custom/asl3-node-list/node-list"
```

Replace `576336` with the node being tested.

## Automatic updates

The installer creates a systemd path watcher. The announcement is rebuilt when these locations change:

- `/etc/asterisk/rpt.conf`
- `/etc/asterisk/custom/rpt`
- `/etc/asterisk/local/node-list-announce.ini`

Check its status:

```bash
sudo systemctl status asl3-node-list-update.path --no-pager
```

View recent rebuild logs:

```bash
sudo journalctl -u asl3-node-list-update.service --no-pager -n 100
```

## Files installed

```text
/usr/local/sbin/asl3-node-list-update
/usr/local/sbin/asl3-node-list-uninstall
/etc/asterisk/local/node-list-announce.ini
/etc/asterisk/custom/rpt/node-list-announcer.conf
/usr/share/asterisk/sounds/custom/asl3-node-list/node-list.ul
/etc/systemd/system/asl3-node-list-update.service
/etc/systemd/system/asl3-node-list-update.path
```

Backups of files changed by the installer are stored under:

```text
/var/backups/asl3-node-list-announcer/
```

## Upgrading from an earlier version

Run the Version 0.3.0 installer over the existing installation:

```bash
sudo ./install_asl3_node_list_announcer.sh
```

The installer replaces the managed updater and DTMF include, backs up existing managed configuration files, and rebuilds the announcement. The old standalone silence patch is not required after Version 0.3.0 is installed.

## Troubleshooting

### DTMF is decoded, but nothing plays

Confirm the installed command:

```bash
sudo cat /etc/asterisk/custom/rpt/node-list-announcer.conf
```

Confirm the audio file exists:

```bash
sudo ls -lh \
  /usr/share/asterisk/sounds/custom/asl3-node-list/node-list.ul
```

Confirm Asterisk can read it:

```bash
sudo -u asterisk test -r \
  /usr/share/asterisk/sounds/custom/asl3-node-list/node-list.ul \
  && echo "Asterisk can read the announcement"
```

Test direct playback:

```bash
sudo asterisk -rx \
  "rpt playback NODE_NUMBER /usr/share/asterisk/sounds/custom/asl3-node-list/node-list"
```

### The installer reports a DTMF conflict

This is intentional protection. A command can conflict even when the full number is not already assigned. For example:

```text
Existing command: *99
Requested command: *997
```

Because `*99` is a prefix of `*997`, app_rpt may complete the shorter command before the final digit can select the new function. Choose one of the alternatives printed by the installer.

### Rebuild the report after editing configuration

```bash
sudo asl3-node-list-update --print-message --verbose
```

### Review Asterisk messages

```bash
sudo journalctl -u asterisk --since "10 minutes ago" --no-pager
```

## Uninstallation

Run:

```bash
sudo asl3-node-list-uninstall
```

The uninstaller removes the generated announcement, managed DTMF include, updater, watcher, service, and local configuration. It leaves the official `asl3-tts` package installed because other ASL3 features may use it. Backup files are also retained.

The original installer may also be used:

```bash
sudo ./install_asl3_node_list_announcer.sh --uninstall
```

## Testing status

Version 0.3.0 incorporates behavior verified on ASL3 node **576336** with app_rpt **3.9.3**:

- Direct announcement playback
- RF DTMF activation using `*698`
- Detection of the inherited `*99` prefix conflict with `*997`
- Two-second squelch-opening silence before speech
- Multiple local-node detection

No installer can account for every customized ASL3 configuration. Review the displayed conflict information and keep the generated backups.

## Project credit

Concept, live testing, and project direction:

**Freddie Mac, KD5FMU — Ham Radio Crusader**

Initial implementation assistance:

**OpenAI ChatGPT**

## License

Released under the MIT License. See `LICENSE`.
