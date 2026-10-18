<p align="center"><img src="Resources/Icons/AppIcon.png" width="96" alt="Jotway icon"></p>

# Jotway

**Quick notes, straight to Apple Notes.**

Jotway gives you a small panel to write a note from anywhere on your Mac. Capture an idea, a reminder, or a few lines from a meeting, then get back to what you were doing. Your notes live in Apple Notes.

**English** · [简体中文](README.zh-CN.md)

Requires macOS 15 or later. This README describes the current source build; release downloads may differ.

## Write a note

1. Press your global shortcut to open the panel.
2. Write what you want to remember.
3. Check **Save to Notes** and press **Enter**.

Jotway handles the save in the background. View the saved text in your chosen Apple Notes folder. Your full original text is preserved, whether saved as a new note or added to a related note with daily grouping enabled.

## Start faster with templates

Use a template when you want a starting point for an idea or a problem.

1. Type `@` in an empty quick-input panel and choose a template.
2. Fill in the fields. **Tab** moves forward; **Shift+Tab** moves back.
3. Check **Save to Notes** and press **Enter** when you're ready.

The built-in templates start as **记录想法** (Capture an idea) and **梳理问题** (Work through a problem). Choosing a template fills your draft; saving still needs your confirmation.

For example, Capture an idea guides you through three prompts: the idea, why it's worth doing, and the next step.

Edit the built-ins or add your own in **Settings → Templates**. Reuse a format for meeting notes, daily reflections, or anything you write often.

## Set up once

1. Choose a global shortcut in the welcome guide.
2. Open **Set Up Notes**, click **Allow Access**, and grant macOS Automation access to Apple Notes.
3. Return to your draft and press **Enter** again to save.

Jotway selects a default Notes folder during setup. Change it in **Settings → Apps → Apple Notes**. See the [first-use guide](docs/product/first-use.md) for details.

## While writing

Switch to a **temporary sticky note** to keep your draft visible above other windows while you work. Both modes share the same text. Return to quick input when you're ready to save.

- **Shift+Enter** adds a line.
- Hide the panel and reopen it to continue your draft.
- Drafts stay in memory while Jotway runs. Quitting, crashing, or restarting clears unsent drafts.

## Your text and privacy

Typing does not request an AI model. Notes title generation uses configured AI providers; grouping, writing help, and requested notes reviews can also send relevant text. A configured fallback may send the same input to a second provider, with separate billing.

When Local Records is enabled, it can store unsent drafts on your Mac, with a default retention of 90 days. Review capture, export, and deletion controls in [settings](docs/product/settings.md).

## Build from source

Requires Swift 6.2 and the macOS 26 SDK.

```bash
swift build
swift test
./scripts/build-app.sh
```

See the [documentation](docs/jotway.md), [development environment](docs/development/environment.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
