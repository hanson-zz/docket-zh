<div align="center">

<img src="docs/images/icon.png" alt="Dockling icon" width="128">

# Dockling 码头

### A free Dock shelf for macOS with an optional Pro upgrade and a red panda desktop pet, in English and Simplified Chinese.

**Website: [docket.shiduo.app](https://docket.shiduo.app)** · [简体中文](README.md) | English

Put a shelf of live widgets, app groups and folders next to the macOS Dock,
or use it in place of the Dock.

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](#build-from-source)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](project.yml)
[![License: MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

<img src="docs/images/en/shelf-showcase.png" alt="The Dockling shelf: clock, world clock, system activity, a sticky note, then a row of app icons" width="100%">

</div>

---

## What Dockling does

- **A shelf next to the Dock** with live widgets, app groups and folders, or use it in place of the Dock.
- **60+ widgets**: calendar, to-dos, focus timer, weather, radio, clipboard, screenshots, Calc and more. Click one for its details panel.
- **A red panda desktop pet** that stashes files, fetches new downloads and reminds you to stand up.
- **Window and app switching**: a ⌘Tab-style App Switcher, three window switcher styles and full-size previews.
- **Message island**: WeChat and other messages drop from the notch.
- **Layouts** switched by shortcut, Focus mode or ⌘ + scroll, and written back to Apple's Dock.

The interface is in **English and Simplified Chinese** and follows the system language. The basics are free; **Dockling Pro** is a one-time purchase, see the [website](https://docket.shiduo.app).

Dockling is an unofficial fork of [Docket](https://github.com/nparashar150/dockset) (MIT) that has grown into its own app.

## In development (next version)

- ✦ **AI Assistant widget and Notch Chat work together**: the widget's ask panel is reorganised into a header (current service, a mode tag, the Pro Notch Chat switch and a settings gear), a large input box in the middle ("What can AI do for you?", with Enter to send · Shift+Enter for a new line in the corner; while a Chinese input method is composing, Return still only confirms the candidate), a row of quick action chips (Ask from Screenshot, Use Clipboard, Translate and Summarize by default; Polish and Explain can be swapped in from the settings page, up to four) and a footer (switch service, what sending will do, Send). Tile management, open modes and API keys move into an Assistant Settings page behind the gear. The widget and Notch Chat share the current service. In API and web mode, sending first closes the widget panel and then opens the chat from the notch; the request lives on the shared chat session, so closing the panel does not stop the answer. Web mode only copies the question and asks you to paste it, never claiming it was sent; app mode only hands off to the app. The Notch Chat header gains a mode tag and a close button, quick actions are collapsed by default so the conversation gets more room, every answer has Copy and the last one can be regenerated, and the input reads "Ask a follow-up…". Collapsed, hovering the notch shows "✦ AI Assistant", and while answering it shows "<service> is thinking" with three dots (still with Reduce Motion). When a notch island such as the focus timer or a download is showing, the chat panel opens below it instead of covering it. Not yet verified on a physical Mac.
- 🐼 **Notch Island follows your focus mascot, and the focus panel gets props**: the focus timer on the notch now follows the mascot chosen in the focus panel (the red panda without Pro, same as the panel), using that mascot's own art for the small head when collapsed and for focusing, paused (napping) and just finished or on a break when expanded; next to the focus ring, on the side where the red panda's bamboo pole stands, the Shiba, cat, penguin, otter and octopus each get a prop that floats gently while focusing and stays still with Reduce Motion, while the red panda keeps climbing its pole. All 20 notch pictures for the five mascots and their 5 props are in; if a picture is ever missing, the notch falls back to the hanging red panda (blinking only then), the collapsed head falls back to the panel picture, and a missing prop is simply not drawn. Not yet verified on a physical Mac.
- 💧 **AI quota water level now shows what is left, and supports Claude**: the water level in the live icons shows how much of the limit remains instead of how much is used, using whichever of the 5-hour and weekly limits is tighter, and falling back to the other when one has no data or is past its reset time; the percentage label shows what remains too. A new Claude switch (on by default) reads the account the Claude command-line tool is signed in to on this Mac (the keychain first, then ~/.claude/.credentials.json), read-only with nothing uploaded; the token goes only to Anthropic and is never refreshed by Dockling. Nothing is drawn when you are not signed in, and no API key is asked for. The first time it reads, macOS may ask whether Dockling may use that keychain item. It now follows the design: the water is tinted per app (blue for ChatGPT, deep orange for Claude, purple for Codex) with a bright surface line that sways gently at a low frame rate, pauses while the shelf is off screen and stays still with Reduce Motion; the percentage is now large bold white text in the lower-left corner; and hovering over an AI icon adds a glass capsule under its name with a countdown such as "Resets in 1d 18h". Settings now have an AI usage level switch with ChatGPT, Claude and Codex checkboxes (Codex gets its own switch, carried over from the old shared one) and a Show: choice of 5 hours, Weekly or Tighter (the default); with one limit fixed, nothing is drawn when that limit has no data. ChatGPT and Codex share the Codex usage data. Tuned after testing on a Mac: the water fills only the lower part of the icon (about 60% when full) so the app logo always shows, and is slightly translucent; the percentage stays inside the icon and shrinks if it does not fit; below 15% left the water turns warm red; and right-clicking the ChatGPT or Codex icon adds Show Quota Usage, which opens the AI usage panel, while a normal click still opens the app. Not yet verified on a physical Mac.
- 💬 **Live icons: unread messages**: Messages, WeChat and Mail show their unread count in the top-right corner, and the badge and icon bounce once when something new arrives (bursts within a second count as one). The count is read only from each app's own badge in the system Dock (Accessibility access needed); only the number is read, never the messages or the screen, and the icon stays as it is when no count can be read, so no made-up numbers. Two styles: Subtle (default) keeps the app's colours; Playful shifts colour with the count, blue for 2 to 3, purple for 4 to 6, magenta for 7 to 8 and red-pink for 9 or more, with a sparkle, flame or drip by the badge (still, not flashing). Settings, Shelf, Live icons has a checkbox per app, the style switch and a 0 to 9 preview. Mail also gets three states from the reference: three warm rays flash in the top-left when new mail arrives; an orange pencil sits in the bottom-right while a compose window is open (Accessibility, looking for a Send button in the window toolbar); a small spinning blue ring shows while mail is in the Outbox (AppleScript, counting Outbox messages only). The opening envelope would mean redrawing Apple's icon, so it is left out. With Reduce Motion nothing bounces or flashes and the ring stays still. Not yet verified on a physical Mac.
- 🧭 **Live icons: Chrome and Safari**: when the pointer rests on the icon, Chrome's coloured disc gives a small turn and springs back and Safari's compass dial sways twice and settles, with the frame staying still. While Chrome's current tab is loading, a thin blue arc now runs along the icon's edge and fades out when it finishes (the old whole-icon spin and launch spin are gone). Safari pages get the same arc while loading (read from the toolbar's Stop button, needs Accessibility permission). A blue download badge sits in the corner while a file is downloading into Downloads, with real progress for Safari, and a purple play badge with a soft glow while the browser plays sound. Nothing is drawn when the state can't be read, and there is no fake progress. Safari has its own toggle; with Reduce Motion nothing turns or runs, and the badges stay static. Not yet verified on a physical Mac.
- 🗑️ **Delete widgets in Widget Management**: each placed widget in Settings ▸ Widget Management now has a trash button (also in its right-click menu) that removes it from the shelf along with its settings after you confirm; the switch still just hides it. Not yet verified on a physical Mac.
- 🌗 **Radio, Photo Frame, Wallpaper and Perfect Day panels follow the appearance**: like every other panel they are light Liquid Glass with dark text in Light and a dark panel with white text in Dark, instead of always dark; text on photos and wallpapers stays white, and the shared basket image stays dark green. The Radio's Classic look and the LED Matrix, Porcelain Dial, Handheld Pixel and Ink Ruler skins follow Light or Dark (LED Matrix keeps its black display housing); the three retro skins and Smoked Glass are designed only for dark and stay dark when chosen. Not yet verified on a physical Mac.
- 🎞️ **Album Wide is now a film strip**: the photo showing now on the left, the next two stacked on the right, so it no longer looks like a wider Standard; the caption is always there, with the date and place when the photo has them, or the folder name and position when it does not. Not yet verified on a physical Mac.
- 🏝️ **Notch Island** (Pro): download progress, the focus countdown, the radio and a plug-in notice grow as a black island out of both sides of the notch, a second activity splits off as a small round island, and hovering expands a frosted glass card to pause, change station or set the volume; screens without a notch get the same shape centered at the top. Countdown card timers show there too (the one ending first when several run, with pause and end acting on that one), the meeting countdown joins the island right after timers, and the island tucks away while the volume or brightness hint shows, so it no longer overlaps the Live Alerts capsule. Not yet verified on a physical Mac.
- ✨ **Live icons** (off by default, Settings ▸ Shelf, with separate switches for Finder, Chrome and ChatGPT/Codex): the icons themselves move instead of wearing little badges. Chrome's icon spins steadily while the current tab is actually loading and eases back to rest when it finishes (needs permission for Dockling to control Chrome; without it the icon only spins once at launch); the ChatGPT and Codex icons hold a translucent water level showing how much of the Codex 5-hour limit is used, hidden when there is no data, and a soft white light travels around the icon's edge while Codex is working; Finder's whole icon becomes a red panda whose eyes follow your pointer (no Accessibility permission needed), drift back to center three seconds after it stops, and blink every few seconds, now and then twice. Nothing spins or flows with Reduce Motion on, the panda's eyes stay centered and don't blink, and Low Power Mode slows it down. Not yet verified on a physical Mac.
- 🦊 **Focus mascots**: pick a red panda, shiba, tabby, penguin, otter or octopus in the focus panel (red panda by default; the red panda is free, the other five are Pro), each with a waiting, focusing, break and just-finished look, and the Notch Island shows the mascot on the left and the time left on the right during focus; with the red panda the bamboo climb stays. Before a session starts, drag the big countdown left or right to set the length in 5 minute steps (5 to 90 minutes, with a trackpad tap at each step), choose a system sound for focus end and break end (preview, repeat or turn off), get a notification when a session ends, plus Skip and today's finished count. Not yet verified on a physical Mac.
- 🎋 **Hanging red panda**: while focus runs on the Notch Island, the collapsed island shows a little red panda head peeking out under the notch (with the red panda mascot); hover and the panda drops down from the notch, tail wrapped around a thin rope, holding a frosted glass timer (round, time left, pause or resume, end, progress bar). It keeps its eyes open, blinks every few seconds and sways gently during focus, dozes with a floating zZ and a dimmed time while paused, and grins on finish and during breaks; with Reduce Motion on it neither sways nor blinks. Countdown card timers keep their card. Not yet verified on a physical Mac.
- 🐾 **Pet steps aside for the shelf**: when the desktop pet curls up on the bottom edge and Dockling's shelf sits there too (including when it slides out from auto-hide), the pet moves beside the shelf instead of hiding behind it with only a few blades of grass or its ears showing; if neither side has room it stays out of sight. Not yet verified on a physical Mac.
- 🤝 **Makes way for Shiduo**: when Shiduo's notch shelf opens, Dockling's Notch Island tucks away and comes back once the shelf closes. Not yet verified on a physical Mac.
- 🐾 **Desktop pet follows your mascot**: with Pro, picking the shiba, ginger cat, penguin, otter or octopus in the focus panel turns the Dock pet into that mascot too: walking, running and carrying files alternate two bouncing frames, sleeping and curling up use its sleeping pose, cheers and waves its cheer, peeks its peek, hanging from the top edge, hugging a side edge and being picked up each have their own pose, and the rest of the time it sits. The red panda keeps its full frame-by-frame animation, and any missing picture falls back to the red panda. Not yet verified on a physical Mac.
- 👀 **Desktop pet peeks by the pointer and hides during calls**: Settings ▸ Widgets ▸ Desktop Pet adds Peek by Pointer (off by default): when the mouse stays still for about 20 seconds, your chosen mascot (the red panda without Pro, in its focus pose while focusing) peeks out at the lower left of the pointer, looking up at it and hides as soon as you move, type, click or scroll; it stays away while you are typing and also hides after about 3 minutes away. While still it is a single picture with no display refresh, and with Reduce Motion it only fades in. Hide During Calls (on by default) hides the pet and the peek while the microphone is in use (calls, meetings) and brings them back after you hang up; Dockling only checks whether the microphone is on and never records. The peek window takes no clicks or focus and stays out of screen sharing and recordings where macOS allows it. All six have their own peek art, falling back to the focus panel's standing picture if one is missing. Not yet verified on a physical Mac.

## New in v1.0

- 🐼 **Red panda desktop pet**: lives on any screen edge; drop files on it to stash them, it fetches new downloads and cheers when a focus session ends
- 🎨 **Custom Dock icons** for any app, Option-drag an image onto it (Pro)
- ⌨️ **Typing sounds**: 7 keyboard and typewriter sounds, plus Mechvibes packs (Pro)
- 🌐 **Automatic input sources** per app
- 🪟 **App Switcher v2**: big icon grid with window thumbnails (Pro)
- 🔮 **New widgets**: Fortune, Pull a Tooth, Minesweeper
- 📌 **Pin to Desktop** and **system widgets** (beta)

Full notes: [changelog](docs/en/changelog.md). Every widget with screenshots: [screenshots](docs/en/screenshots.md).

## Features

More than fifty widgets, grouped by use. Mix them freely on one shelf.

- **Apps, files and quick access**: app groups, folders, Downloads, File Shelf, Clipboard, Screenshots, Photo Frame, Bookmarks, App Switcher, Shortcuts, Search.
- **Productivity and focus**: Calendar, Week Agenda, Reminders, Quick To-do, Sticky Note, Focus Timer, Habits, Stand Up reminders, Anniversaries, Time Progress, Slacker Clock, AI Assistant, Translate, Codex Usage, GitHub.
- **Mac control and system**: Battery (with charge limit and battery alerts), System Activity, Network Activity, Gauges, Volume, App Volume, Microphone, Quick Toggles, Wallpaper, Trash, Mail.
- **Handy tools**: Calc (calculator, unit converter and currency in one), Color Picker, Emoji, Capture, Recorder, AirDrop.
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
