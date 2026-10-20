# DittoMac

A clipboard manager for macOS, inspired by [Ditto](https://ditto-cp.sourceforge.io) for Windows.

DittoMac lives in your menu bar and saves everything you copy. Open it with a shortcut, search your history and paste any past item into the app you are using. Your history never leaves your Mac.

## Features

- **Clipboard history:** saves text, rich text, HTML, images and files, plus the app each item came from.
- **Instant search:** type to filter your history.
- **Pins:** pinned items stay at the top and are never deleted automatically.
- **Groups:** sort clips into tabs, for example "Work" or "Snippets".
- **Keyboard first:** open the popup from anywhere, move with the arrow keys, paste with Enter.
- **Quick paste:** paste any of your 10 latest items without opening the popup.
- **Multi-select:** select several clips and paste them as one block. Copying a selection saves it as a new combined clip.
- **Drag and drop:** drag images and files out of the popup into Finder, a browser or a chat app.
- **Smart duplicates:** copying the same content again moves it to the top instead of adding a second copy.
- **History limits:** choose how many items to keep (25 to 5,000) and delete old items after a set number of days.
- **Launch at login.**

## Privacy

Privacy is the core design choice.

- **No cloud, no account, no tracking.** History is stored in a local database on your Mac (`~/Library/Application Support/DittoMac`).
- **Excluded apps:** copies made in apps you choose, such as a password manager, are never saved.
- **Optional LAN sync:** sync history between your own Macs over your local network. Macs find each other with Bonjour, connect directly and encrypt every item (AES-GCM) with a passphrase you set. Nothing goes through a server.

## Install

Requires macOS 13 Ventura or later.

1. Download the latest `DittoMac-x.x.x.dmg` from [Releases](../../releases).
2. Open the DMG and drag **DittoMac** into **Applications**.
3. Open it for the first time. DittoMac is not notarized by Apple, so macOS blocks a normal double-click:
   - **macOS 13 and 14:** right-click (or Control-click) DittoMac in Applications, choose **Open**, then click **Open** again.
   - **macOS 15 and later:** double-click DittoMac once and close the warning. Then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
4. Allow **Accessibility** access when asked (System Settings > Privacy & Security > Accessibility). DittoMac needs it to paste into the app you were using.
5. Using LAN sync? Allow **Local Network** access when asked.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open history | `⌃` + `` ` `` (Control + backtick), or click the menu bar icon |
| Move up / down | `↑` `↓` |
| Select several | `⇧↑` `⇧↓`, `⌘`-click or `⇧`-click |
| Paste selected | `Enter` or double-click |
| Copy selected without pasting | `⌘C` |
| Close | `Esc` |
| Quick paste item 1 to 10 | `⌃⌥1` to `⌃⌥0` |
| Pin, move to group or delete | Right-click an item |

You can change the open shortcut in Preferences. Right-click the menu bar icon to open Preferences.

## Known limitations

- Not notarized, so first launch needs the steps above.
- The sync passphrase is stored in app preferences, not yet in the macOS Keychain.

## Build from source

Requires Swift 5.10 or later (Xcode command line tools).

```bash
./Scripts/build_app.sh   # builds build/DittoMac.app
./Scripts/build_dmg.sh   # builds build/DittoMac-<version>.dmg
```

The build is ad-hoc signed. After each rebuild, macOS asks you to approve Accessibility access again.

**Built with:** Swift, AppKit, SwiftUI, [GRDB](https://github.com/groue/GRDB.swift) (SQLite), Network framework (Bonjour) and CryptoKit.

## Credits

Inspired by [Ditto](https://ditto-cp.sourceforge.io), the open-source clipboard manager for Windows. DittoMac is an independent project. It is not affiliated with Ditto or its authors and shares no code with it.
