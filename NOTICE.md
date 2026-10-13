# Notice and attribution

> **Docket 中文版（Chinese localization fork）：** 本仓库是
> [Docket](https://github.com/nparashar150/dockset)（MIT 许可，版权归其原作者所有）的
> **非官方简体中文本地化分支**，仅翻译了界面文字并调整了构建配置。本分支与 Dockset、
> Docket 上游及其作者均**无任何关联**，也未获得其认可或赞助。This repository is an
> unofficial Simplified Chinese localization fork of Docket
> (https://github.com/nparashar150/dockset, MIT, © its author). It is not
> affiliated with, endorsed by, or connected to Dockset or the upstream Docket
> project.

## Dockset

Docket exists because of [**Dockset**](https://dockset.app).

Dockset is a macOS app that puts a shelf of live widgets and app groups
alongside the Dock. It is a paid, commercial product, built and supported by an
independent developer - one person's work, sold directly, maintained directly.
It is the original. Docket is not.

**If you want this idea done properly, buy Dockset.** It is the finished,
supported, commercial article, made by the person who thought of it, and paying
for it is how independent Mac software keeps being made. Docket is a hobby
reimplementation written to find out how the thing works; it has rough edges,
no support, and no promises. Those are not competing sentences. They are the
honest ordering.

### What Docket is not

- Docket is **not affiliated with, endorsed by, sponsored by, or connected to**
  Dockset or its developer, in any way.
- Docket is **not "the free version of Dockset"**, not a replacement for it, and
  not an alternative being offered in its place.
- Nothing here is a claim that Docket is better, more complete, or more correct
  than Dockset. It isn't, and this file is not the place to pretend otherwise.

### What was taken, precisely

No code. No artwork, icons, or app assets. No screenshots. No marketing copy or
website text. No name, logo, wordmark, or branding. Nothing was decompiled,
extracted, or copied out of the Dockset app or its site.

What *was* taken is the idea, and the visual target. Dockset showed that a shelf
beside the Dock could hold live widgets and app groups and still feel like part
of macOS. Everything under `Sources/` is an independent implementation of that
idea, written against Apple's frameworks, and then tuned by looking at the
published product and measuring the gap.

Two of those measurements are recorded in the source, and they are the most
concrete debt this project owes:

- **Card luminance.** `Sources/Widgets/WidgetContext.swift` notes that Dockset
  holds a widget card at roughly 0.85× the luminance of the plate behind it.
  Docket's first attempt tinted cards with `Color.primary`, which is white in
  dark mode and lightened the card until it matched the shelf exactly - a card
  of 40 on a plate of 40, which is to say no card at all. Reproducing that 0.85
  ratio with a black tint is what made cards read as recesses in the plate
  rather than panels floating on it.
- **The 2×2 folder grid.** `Sources/Core/Models.swift` fixes an app group's
  closed tile at four preview icons in a 2×2 grid, as Dockset does. It is not a
  preference and it is not arbitrary: the tile is one Dock slot wide, and a
  third column shrinks the artwork below the size at which it is legible. That
  reasoning was arrived at by looking at a version that had already got it
  right.

Naming these is the point. A general thank-you costs nothing; saying exactly
which decisions were learned from someone else's careful work is the part that
is actually owed.

---

## Third-party services and data

### MET Norway - weather data

The weather widget is backed by the **Norwegian Meteorological Institute (MET
Norway)** Locationforecast 2.0 API (`api.met.no`), used without an API key under
MET's [terms of service](https://api.met.no/doc/TermsOfService).

The data is licensed **[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)**,
which requires the attribution to be visible wherever the data is shown - not
buried in a credits file. Docket honours that in the UI: `WeatherService`
carries the string

> Weather data from MET Norway

as `WeatherService.attribution`, and `Sources/Widgets/Details/WeatherDetail.swift`
renders it in the weather detail panel. **If you add another surface that
displays this data, it must carry that attribution too.** MET's terms also
require a descriptive `User-Agent` with a real contact on every request, which
`WeatherService` sets.

### Open-Meteo - daily forecasts

The weather widget's 7-day, 10-day and multi-city layouts, and the 10-day
list in its detail panel, read daily forecasts from
**[Open-Meteo](https://open-meteo.com/)** (`api.open-meteo.com`), free and
without an API key under its
[terms](https://open-meteo.com/en/terms). The data is licensed
**[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)**. The weather
detail panel shows `WeatherService.forecastAttribution`:

> 部分天气数据来自 Open-Meteo

`ForecastService` caches each place and asks at most once every 30 minutes,
well inside the free tier's non-commercial limits.

### Yahoo Finance - stock quotes

The Stock and Watchlist widgets read Yahoo's chart endpoint
(`query1.finance.yahoo.com`). This is an **undocumented, unofficial endpoint**
with no published licence or support commitment - it is not a contract, fields
come and go, and it rejects non-browser clients. `StockService` treats every
field as optional and every failure as "keep the last good value and mark it
stale" for exactly that reason. Quotes are informational only and are not
suitable for any financial decision. Yahoo and Yahoo Finance are trademarks of
Yahoo Inc.

### CoinGecko - cryptocurrency prices

The 加密货币行情 widget reads CoinGecko's free public API
(`api.coingecko.com/api/v3/coins/markets`) without a key: prices, 24-hour
change and the hourly sparkline. `CryptoService` asks at most once every five
minutes, keeps the last good answer in Caches, and marks it stale when a
refresh fails rather than blanking it. CoinGecko's terms ask that the data be
credited where it is shown, so `CryptoMarket.attribution`

> 数据来自 CoinGecko

is rendered, with a link to [coingecko.com](https://www.coingecko.com), in
`Sources/Widgets/Details/CryptoDetail.swift`. **Any other surface that shows
these prices must carry the same credit.** Prices are informational only and
are not suitable for any financial decision. CoinGecko is a trademark of its
owner.

### Codenotch - Codex usage endpoints

The Codex usage widget (`Sources/Core/CodexUsage.swift`,
`Sources/Services/CodexService.swift`) reads the same ChatGPT backend
endpoints (`chatgpt.com/backend-api/wham/usage`, `/wham/profiles/me`,
`/wham/rate-limit-reset-credits`) and the same local Codex files
(`~/.codex/auth.json`, `~/.codex/sessions/**/rollout-*.jsonl`) that
[**Codenotch**](https://github.com/vinzdg/codenotch) does. Which endpoints
exist, which headers they want, how their payloads are shaped, and which
session-log events mark a turn starting and ending were learned from
Codenotch's source. Docket's code is a fresh, smaller implementation in its own
style; any part of it that follows Codenotch closely is used under Codenotch's
licence:

> MIT License
>
> Copyright (c) 2026 Vinz
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

These ChatGPT endpoints are **undocumented and unofficial**. OpenAI publishes
no contract for them and can change them at any time; the widget keeps the
last good reading and says so when one fails. The Codex sign-in is only ever
read, never written or refreshed, and the token is sent to chatgpt.com only.
OpenAI, ChatGPT and Codex are trademarks of OpenAI.

### OnlySwitch - quick switches

The 快速开关 widget (`Sources/Core/QuickToggleList.swift`,
`Sources/Services/QuickActions.swift`) offers the same kinds of switches as
[**OnlySwitch**](https://github.com/jacklandrin/OnlySwitch) and uses the same
public commands for them: Finder's `AppleShowAllFiles` and `CreateDesktop`
keys and `NSGlobalDomain AppleShowAllExtensions` followed by `killall Finder`,
Finder's `eject (every disk whose ejectable is true)`, the AppleScript input
volume for muting the microphone, and an IOKit `NoDisplaySleep` assertion for
Keep Awake. Docket's code is its own; anything that follows OnlySwitch closely
is used under its licence:

> MIT License
>
> Copyright (c) 2021 jack
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

### holiday-cn - Chinese public holiday data

The 农历与假期 widget reads the State Council's yearly holiday notices as
published by [**holiday-cn**](https://github.com/NateScarlet/holiday-cn)
(MIT), fetched at run time through jsDelivr; the 2026 schedule is bundled in
`Sources/Core/ChineseCalendar.swift`. The schedule itself is an official
government notice (gov.cn).

### BananaBin - the idea of flies on the Trash

The 废纸篓 widget's flies, which appear once the Trash passes a chosen size,
multiply every hour it is left and scatter under the pointer, are an idea from
[BananaBin](https://bananabin.app) by Leon Schrijvers and Rik Schennink.
BananaBin is a paid, closed-source app; none of its code or artwork is used,
only the idea, drawn and written from scratch.

### Apple

Docket is built entirely on Apple's own frameworks - SwiftUI, AppKit,
Foundation, Observation, MapKit, CoreLocation, CoreServices, EventKit and
IOKit - and uses **SF Symbols**, which Apple licenses for use on Apple
platforms under the terms accompanying the SF Symbols app and Xcode. No Apple
asset is redistributed here.

### Build tooling

The Xcode project is generated by [**XcodeGen**](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. XcodeGen is MIT licensed and is a developer tool only - it
is not linked into, or shipped with, the app.

### Bundled dependencies

**There are none.** Docket has no Swift Package Manager dependencies, no
CocoaPods, no Carthage, and no vendored third-party source. Everything under
`Sources/` was written for this project (the Codex usage widget follows
Codenotch's findings and the quick switches follow OnlySwitch, as described
above).

---

## Trademarks

Apple, macOS, Mac, Finder, Dock, Apple Music, AirDrop, Xcode, SwiftUI, and SF
Symbols are trademarks of Apple Inc., registered in the U.S. and other
countries. Spotify is a trademark of Spotify AB. Yahoo is a trademark of Yahoo
Inc. OpenAI, ChatGPT and Codex are trademarks of OpenAI. **Dockset** and its
branding belong to its developer.

All of these marks are used here only to describe what Docket interoperates
with or what it was inspired by. None of these companies or developers are
affiliated with Docket, and none of them have endorsed it.

---

## Docket's own licence

Docket itself is released under the MIT License - see [LICENSE](LICENSE).
That licence covers Docket's source only. It does not extend to any third-party
data or service named above, each of which carries its own terms.
