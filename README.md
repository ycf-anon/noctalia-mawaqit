# Mawaqit for Noctalia V5

Prayer times plugin for Noctalia V5 with live countdown, notifications, and azan support.

![Mawaqit Screenshot](assets/mawaqit.png)

## Features

- Daily prayer times
- Live countdown
- Notifications and azan
- Configurable location
- Bar widget and panel view

## Status

Work in progress. Porting the original QML Mawaqit plugin to Noctalia V5.

## File Structure

```text
mawaqit/
├── plugin.toml
├── bar_widget.luau
├── panel.luau
├── service.luau
├── translations/
│   ├── en.json
│   ├── fr.json
│   └── tr.json
└── assets/
    ├── azan1.mp3
    ├── azan2.mp3
    ├── azan3.mp3
    └── mawaqit.png
```

## Install

```bash
cp -r mawaqit/ ~/.local/share/noctalia/plugins/

noctalia msg plugins enable ycf/mawaqit
```

## Azan Files

The plugin plays azan using `paplay` (PipeWire/PulseAudio) or `pw-cat` as a fallback.

Copy your `.mp3` files into the `assets/` folder:

```bash
mkdir -p ~/.local/share/noctalia/plugins/mawaqit/assets

cp azan1.mp3 ~/.local/share/noctalia/plugins/mawaqit/assets/
cp azan2.mp3 ~/.local/share/noctalia/plugins/mawaqit/assets/
cp azan3.mp3 ~/.local/share/noctalia/plugins/mawaqit/assets/
```

Original azan files can be found in the legacy plugin repository.

## Settings

Open **Settings → Plugins → Mawaqit** to configure:

- City and country
- Calculation method
- Notifications
- Azan playback

Bar widget settings (colors, icon, display mode, etc.) are configured separately from the widget settings menu.

## Usage

- Right click → Open prayer times panel
- Left click → Cycle display mode:
  - Countdown
  - Static time
  - Prayer name only

## Notes from Porting

### Settings hot-reload for services

When a user changes their city in the plugin settings, the service continues using the old value until it is restarted.

### `follow_redirects` default behavior

The Aladhan API returns redirects. Because `follow_redirects` is disabled by default, requests appeared to fail with what looked like a normal network error.

### Custom fonts in panel labels

`barWidget.setFont()` works for bar widgets, but there doesn't seem to be an equivalent for `ui.label` in panels.

Needed for Arabic text with `DecoType.ttf`.

### Container opacity affects children

Applying `opacity` to a container such as `ui.column` also affects all child widgets.

Couldn't find a way to make only the background semi-transparent while keeping the text fully opaque.
