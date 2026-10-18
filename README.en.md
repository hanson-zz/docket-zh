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

<img src="docs/images/en/shelf-showcase.png" alt="The Dockling shelf: clock, world clock, system activity, a sticky note, then a row of app icons" width="100%">

<sub>Screenshots show the app's own English interface, taken on macOS by the screenshot tool in this repository (see "How the screenshots are made" below).</sub>

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

## Screenshots

<sub>Widgets on the shelves below show the widget library's own sample data, so nothing is read from the capture machine's calendar, music or files. Panels marked "sample data" do the same; the rest are live readings taken at capture time.</sub>

**Apps, files and quick access**

<img src="docs/images/en/shelf-files.png" alt="Shelf with Downloads, Recent Screenshots, File Shelf, Search, AirDrop and app icons (sample data)" width="100%">

**Productivity and focus**

<img src="docs/images/en/shelf-productivity.png" alt="Shelf with Calendar, Reminders, Focus Timer, Water and a sticky note (sample data)" width="100%">

**Mac control and system**

<img src="docs/images/en/shelf-system.png" alt="Shelf with Now Playing, Volume, Quick Toggles, System Activity and Battery (sample data)" width="100%">

**Handy tools**

<img src="docs/images/en/shelf-tools.png" alt="Shelf with Clipboard, Unit Converter, Emoji, Weather and a Tokyo world clock (sample data)" width="100%">

**Shelf looks**: dark glass with monochrome widgets.

<img src="docs/images/en/shelf-styles.png" alt="Dark glass shelf in monochrome: analog clock, weather with wind and sunrise, Tokyo world clock and calculator (sample data)" width="100%">

**Liquid looks** (Dockling Pro): Time Progress, Water, Focus Timer, System Activity and Battery as a glass of water that fills with progress, load or charge.

<img src="docs/images/en/shelf-liquid.png" alt="Shelf with the liquid looks of Time Progress, Water, Focus Timer, System Activity and Battery (sample data)" width="100%">

**Colors and backgrounds**: fifteen preset colors, a custom color or the system accent, on a dark, frosted, gradient, dotted or lined card.

<img src="docs/images/en/shelf-colors.png" alt="Shelf with a pink gradient countdown, mint frosted Water, purple dotted to-do, orange gradient Time Progress ring, sky blue lined Habits and a blue Calendar on a dark card (sample data)" width="100%">

**World clocks with a city picker**

<img src="docs/images/en/shelf-world.png" alt="Shelf with the local clock and world clocks for Tokyo, London, New York and San Francisco" width="100%">

**New quick tools**: Text from Screen, QR Code, Color Picker, Mirror, Presentation Mode and Keyboard Lock, next to the AI Assistant card and Capture.

<img src="docs/images/en/shelf-quick-tools.png" alt="Shelf with Quick Toggles (Text from Screen, QR Code, Color Picker, Mirror, Presentation Mode, Keyboard Lock, Dark Mode, Keep Awake), the AI Assistant card and Capture (sample data)" width="100%">

<p align="center">
  <img src="docs/images/en/widget-library.png" alt="Add Widget sheet: category sidebar on the left, Health and Habits on the right, with orange Pro capsules on the liquid look and the extra characters (sample data)" width="100%"><br>
  <sub>Add Widget: category sidebar and Pro capsules</sub>
</p>

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/en/time-progress.png" alt="Time Progress panel: how much of today, this week, this month and this year has passed" width="100%">
      <p align="center"><sub>Time Progress: day, week, month and year</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/en/battery.png" alt="Battery panel: the Mac, AirPods Pro and Magic Mouse charge levels (sample data)" width="100%">
      <p align="center"><sub>Battery: the Mac and accessories (sample data)</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/en/ai-notch.png" alt="AI notch chat panel: red panda, service chips, clipboard and quick action buttons, and the question box in Jump mode" width="100%">
      <p align="center"><sub>AI chat that grows out of the notch (Jump mode)</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/en/pro-paywall.png" alt="Dockling Pro paywall: the Pro feature list, a 7 day free trial, buy and early bird price, and the license key field" width="100%">
      <p align="center"><sub>Dockling Pro: features, trial, purchase and license key</sub></p>
    </td>
  </tr>
</table>

<p align="center">
  <img src="docs/images/en/clipboard.png" alt="Clipboard panel: the four most recent copies" width="50%"><br>
  <sub>Clipboard: recent copies, searchable, with starred items</sub>
</p>

## In development (next version)

- **The single and multi Anniversaries cards now look nothing alike**: the single card is a tear-off calendar page. On the left a small white page has the name on a strip in the date's colour, the day in large type and the month below, in lunar terms for lunar dates; on the right are “since” or “to go”, the day count and a short line: “Year 8 · next anniversary in 214 days” when counting up, or the weekday and “yearly” or the year when counting down. On the day itself (a countdown that arrives, or an anniversary when counting up) the card takes a pale wash of the date's colour, the red panda cheers, it reads “Today” (or “8 years!”) and suggests clicking to make a share image. When the day changes after midnight the old page flips away and the new one shows; with Reduce Motion it simply fades. The setting “Show progress ring (single style)” is now “Show calendar page (single style)”; turned off, only the text remains. The multi card is now a Next 12 Months timeline: the title shows how many dates fall within the year, and the axis runs from today to a year from now with month ticks and quarter labels. Each date is a dot in its colour; the nearest is larger and labelled with its name and days, the others are labelled where they fit and otherwise drawn as dots. Count-ups sit on their next anniversary; dates more than a year away and one-off countdowns that have passed are left off. Clicking a dot (whichever is nearest) opens its page, clicking empty space opens the timeline, and pointing at a dot shows its name and date beside the title. The multi card is a fixed 236 pt wide and the single card 188 pt. On side shelves the single card is a tall tear-off page with the day count, and the multi card lists the nearest three on a short rail, each row opening its date. The widget library previews use the new looks. Positions on the axis, month ticks, label spacing, nearest-dot clicks and the page text are computed in Core with tests. Not yet verified on a real Mac.
- **Reminders can be edited, in sync with Reminders and your iPhone**: the Reminders widget now reads and writes the system Reminders, which iCloud syncs to your iPhone. In the List style each row starts with a circle; click it to complete the reminder, and overdue circles and times are red, with “Yesterday” for yesterday's. Next Reminder shows a countdown such as “in 40 min · 15:00”, and hovering the card shows Done and Snooze 1 Hour (from the due time if it is still ahead, from now if it is late). Count is renamed Today Overview and shows two big numbers side by side, overdue (red when there are any) and due today; placed cards keep working, only a little wider. The panel can now edit: + New Reminder at the top; click a row to edit it in place (title, date and time, both optional, priority None, Low, Medium or High, and list), press Return to save, or delete it there; the context menu has Move to Tomorrow, Move to Next Monday, Snooze 1 Hour, Done, Edit and Delete, keeping the time of day. Saving something not due today says so in a line, and moving a due time moves its alert too. With a list chosen for the widget, the panel shows only that list and new reminders go into it. The card never raises a permission prompt; access is asked for the first time you open the panel. In Add Widget, widgets that need a system permission no longer show a small lock; the permission is named in the card's tooltip instead (Pro capsules are unchanged), and the Reminders heading says “Syncs with Reminders”. Relative times and the postpone dates are computed in Core with tests. Not yet verified on a real Mac.
- **Quick To-do becomes “jot it down, clear it today”, apart from Reminders**: Quick To-do needs no permission and never syncs, with no dates or times, and its heading in Add Widget now reads “Jot it down, never synced”. The card shows Today's three: star up to three items in the panel (or right-click, Mark for Today) and the card shows them first, with how many are done out of how many are marked in the corner and a circle on each row to tick it off; with nothing marked it shows the first open items. Drop text, a link or a file on the card or the panel and a dashed outline reads “Drop to add a to-do”; links and files keep their address and open from a small button on the card and in the panel. Settings, Shortcuts adds Add a Quick To-do (not set by default): it opens a small field near the top of the screen, and Return adds the line to the first Quick To-do on the shelf; Esc or a click outside closes it. Each new day, items finished yesterday are put away on first display, and the panel asks about yesterday's unfinished ones: move them to today or give them up. With everything done, the card shows the red panda, “All clear today” and the streak of cleared days. Right-click, Move to Reminders creates a system reminder for today, tomorrow, a chosen date or no date, then removes the item; Reminders access is only asked for at that moment. Today's three, the daily clear-out and the streak are computed in Core with tests. Not yet verified on a real Mac.
- **Anniversaries open differently from the single and multi cards, with a page per date and a share image**: the single card opens a page for the date it shows, with a large ring for this year's progress (and which year it is when counting up), the name, the day count, the start date and weekday, and the days to the next anniversary. Below are milestones: days 100, 520, 1,000, 1,314, 2,000, 3,000, 5,000 and 10,000 when counting up, or the days 100, 30, 7 and 1 days before when counting down, each with its date and weekday, ticked and dimmed once passed, with a dot on the next one; then the next four anniversaries (which one, the date and weekday, and the days left, with the lunar date for lunar events). “‹ Anniversaries” goes to the timeline, “Switch” changes the date pinned to the card, and the bottom has Edit (the existing editor), Share Image and Manage All Dates. The share image is a tall card in a dark gradient of the date's colour with the red panda, the name, the big number, the date range and “Dockling”; save it as PNG or copy it, free. The multi card still opens the timeline, now with a This Month summary on top (how many dates fall this month and the days to the nearest, click to open it); clicking a column on the card opens that date's page directly, and the column under the pointer lights up a little, on side shelves too. The timeline's context menu adds Open Its Page. Milestones, anniversaries and the month summary are computed in Core with tests. Not yet verified on a real Mac.
- **No more white scroll bar over panels**: with “Always show scroll bars” or a mouse attached, dark panels such as New Habit, Anniversaries, To-do, Water, Radio and AI drew a light scroll bar over their icons and colours. These panels now hide the scroll bar and still scroll with a wheel or trackpad; New Habit fades out at the bottom to show there is more. Not yet tested on a real Mac.
- **Dockling Pro locks the rest, with trial reminders**: Text from Screen, QR Code, Presenting, Lock Keyboard and Low Power Mode in Quick Toggles are now really locked. Until Pro is unlocked they stay listed in Settings with the Pro capsule, and ticking one opens the Pro window; one already on a card is dimmed with a small lock and opens the Pro window instead of running. Presenting, Lock Keyboard or Low Power Mode left on from the trial can still be turned off. The AI notch chat opens the Pro window instead of the chat from the notch or the shortcut, and so does turning it on in Settings, AI; the AI card's red panda falls back to the old ask panel, opening websites and apps stays free, and asking in web or API mode opens the Pro window. The battery charge limit's switch and the install and update helper buttons open the Pro window; a limit that was on stops applying (the helper is told it is off, so the battery charges normally) and comes back by itself once Pro is unlocked. A one-time in-app notice appears when one day of the trial is left and again once it has ended, with a button that opens the Pro window to buy or enter a gift code; activated Macs and former supporters never see it. The Pro window lists the new Pro tools. Former supporters stay unlocked. Not yet verified on a real Mac.
- **Dockling Pro covers more, and Add Widget groups cards by widget**: App Volume, Recorder, Stocks, Watchlist, Crypto, Wallpaper, Radio, File Shelf, Translate and Habits are now Pro, alongside Slacker Clock, Time Progress, Ambient Sound, Podcasts, Trash, GitHub, App Switcher, Codex Usage, the Red Panda's Basket and Virtual Pet: 20 Pro widgets and 40 free ones. The multi-city Weather style and the Battery percentage ring are Pro, badged in the library and the style menus; a placed one shows the small lock until Pro is unlocked. Sticky Note keeps its five lightest papers free (Cream, Mint, Peach, Lavender and the default Lemon), the other ten are Pro, and a placed note on a Pro paper falls back to Lemon. In Settings, Widgets, Colors and Background, the presets stay free while the custom color and the gradient background are Pro. Clearer card names: AI Portal (Wide) and AI Portal (Tall) for the AI Assistant, Standard Photo Frame and Wide Photo Frame for the photo frame; only the names changed, placed widgets are untouched. Each category in Add Widget now shows one small heading per widget (with a Pro capsule for whole Pro widgets and a style count), separated by a thin line; search results and Recommended stay flat, and the up and down arrow keys follow the rows as drawn. Not yet verified on a real Mac.

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

## How the screenshots are made

Every image in this README is taken by the screenshot tool in this repository: `Tools/Shots` puts the app's real shelf and panels in real windows on screen, and `scripts/capture-shots.sh` captures them with `screencapture`. They are not mockups and no number is edited by hand.

Run `scripts/capture-shots.sh` for the Chinese interface (written to `docs/images/zh`) or `SHOTS_LANG=en scripts/capture-shots.sh` for English (written to `docs/images/en`). It needs Screen Recording permission for your terminal and takes a few minutes. The **Actions > Screenshots** workflow takes both sets on a GitHub macOS runner and uploads them as an artifact.

## License

[MIT](LICENSE) for the original Docket code. Dockling's own additions are covered by [LICENSING.md](LICENSING.md) and the [EULA](EULA.md).
Third-party attribution and trademarks are in [NOTICE.md](NOTICE.md).
Dockling is not affiliated with, endorsed by, or sponsored by Dockset, CoolDock, upstream Docket or their authors.
