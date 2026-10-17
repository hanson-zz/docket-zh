<div align="center">

<img src="docs/images/icon.png" alt="Dockling icon" width="128">

# Dockling 码头

### A free, open source Dock shelf for macOS, in English and Simplified Chinese.

**Website: [docket.shiduo.app](https://docket.shiduo.app)** · [简体中文](README.md) | English

Put a shelf of live widgets, app groups and folders next to the macOS Dock,
or use it in place of the Dock.

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](#build-from-source)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](project.yml)
[![License: MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

<img src="docs/images/zh/shelf-showcase.png" alt="The Dockling shelf: clock, world clock, system activity, a sticky note, then a row of app icons" width="100%">

<sub>Screenshots show the app's own interface (currently in Chinese), taken on macOS by the screenshot tool in this repository.</sub>

</div>

---

## What it is

Dockling (formerly Docket 中文版) is an **unofficial fork** of [Docket](https://github.com/nparashar150/dockset),
an MIT licensed open source macOS app. It started as a Simplified Chinese localization and has grown into its own app:

- The interface is available in **Simplified Chinese and English** and follows the system language.
  If your preferred languages include neither Chinese nor English (French, Japanese, German and so on),
  Dockling shows English; Traditional Chinese, Hong Kong and Taiwan show Simplified Chinese.
  You can also pick a language in **Settings ▸ General ▸ Language**.
- It builds for anyone who clones it: ad-hoc signing and its own bundle ID (`com.docket-zh.app`),
  so it can be installed next to upstream Docket.
- Dozens of new widgets, clock faces and weather views, shelf looks, per-widget conditions,
  shrink to fit, and three ways to switch layouts.

The basics it shares with upstream:

- **Follows the real Dock**: size, edge, magnification and auto-hide are read live from System Settings.
- **App groups**: drag one icon onto another and hold to make a group, like on iOS.
- **Layouts**: save several and write them back to Apple's Dock (only `persistent-apps` changes, with verification and rollback).
- **Click a widget to open its details panel** with more information and actions.

---

## Features

More than fifty widgets, grouped by use. Mix them freely on one shelf.

- **Apps, files and quick access**: app groups, folders, Downloads, File Shelf, Clipboard, Screenshots, Photo Frame, Bookmarks, App Switcher, Shortcuts, Search.
- **Productivity and focus**: Calendar, Week Agenda, Reminders, Quick To-do, Sticky Note, Focus Timer, Habits, Stand Up reminders, Anniversaries, Time Progress, Slacker Clock, AI Assistant, Translate, Codex Usage, GitHub.
- **Mac control and system**: Battery (with charge limit and battery alerts), System Activity, Network Activity, Gauges, Volume, App Volume, Microphone, Quick Toggles, Wallpaper, Trash, Mail.
- **Handy tools**: Calculator, Unit Converter, Currency, Color Picker, Emoji, Capture, Recorder, AirDrop.
- **Media and fun**: Now Playing (Apple Music, browser tabs, NetEase Cloud Music, Xiaoyuzhou), Radio, Podcasts, Ambient Sound, Virtual Pet, the Red Panda's Basket, Water.
- **Time, weather and markets**: Clock and World Clock, Weather and forecasts, Lunar & Holidays, Stocks, Watchlist, Crypto.
- **Live Alerts**: a small capsule below the notch for volume, brightness and upcoming meetings.
- **Dockling Pro**: a one-time purchase that unlocks extra widgets and looks. The basics are always free.

## Install

1. Download the latest `.dmg` or `.zip` from the [Releases page](../../releases)
   and move `Dockling.app` to Applications.
2. **The build is not signed or notarized**, so macOS 26 warns the first time you open it:
   - Double-click it, then close the warning;
   - Open **System Settings > Privacy & Security** and click **Open Anyway** next to Dockling;
   - Authenticate and confirm.

   Or remove the quarantine attribute in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Dockling.app
   ```

3. **Look in the menu bar on first launch.** Dockling is an accessory app with no Dock icon and no main window.
   Settings, the widget library and layout switching live in the menu bar icon.

### Known limitations

- An ad-hoc signed accessory app gets no location prompt from macOS, so enter a city for the Weather widget in **Settings > Widgets**.
- Now Playing needs Dockling allowed under **Privacy & Security > Automation**; reading browser tabs also needs "Allow JavaScript from Apple Events" in the browser's Develop menu.
- Lunar dates, solar terms, the "Chinese" clock face and the End User License Agreement stay in Chinese in the English interface.

## Build from source

You need macOS 26 and Xcode. The Xcode project is generated from `project.yml` and is not in the repository:

```sh
brew install xcodegen
xcodegen generate
xcodebuild -scheme Docket -configuration Release build
```

Interface text lives in String Catalogs under `Resources/Localization`. Simplified Chinese is the source language and English is the translation. At runtime the development region in Info.plist is English, so languages Dockling does not ship fall back to English, and the Traditional Chinese and Hong Kong tables carry the Simplified text.

## License

[MIT](LICENSE) for the original Docket code. Dockling's own additions are covered by [LICENSING.md](LICENSING.md) and the [EULA](EULA.md).
Third-party attribution and trademarks are in [NOTICE.md](NOTICE.md).
Dockling is not affiliated with, endorsed by, or sponsored by Dockset, CoolDock, upstream Docket or their authors.
