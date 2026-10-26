# Lock In

tiny menu bar focus timer for macOS. no window, no dock icon, ~12MB.

- **timer or flow**: fixed blocks, or count up and earn a break that scales
- **one intention** per block, shown in the menu
- **hides distracting apps** during focus (Slack, Discord, etc, edit the list)
- **dims your screens** on break so you actually get up
- **parking lot**: dump a stray thought, get back to work, review on break
- **pauses when you walk away**
- optional Do Not Disturb via two Shortcuts

## keys

| | |
|-|-|
| `⌃⌥F` | start / pause / resume |
| `⌃⌥B` | end block / start break / skip break |
| `⌃⌥P` | park a thought |

## install

```sh
scripts/build-app.sh --install
```

needs macOS 14+, Swift 6. no dev cert? `LOCKIN_SIGN_IDENTITY=- scripts/build-app.sh --install`

## scripting

`open -g "lockin://start?intent=write%20spec"`. also `toggle`, `stop`, `break`, `skip`, `extend`, `park?text=…`, `quit`. good for Raycast / Shortcuts.
