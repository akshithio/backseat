# backseat

Computer use for macOS that doesn't take over your screen. An MCP server that lets an agent drive apps in the background while you keep using your Mac: your cursor, keyboard focus and Space stay yours.

## How

Nothing backseat does activates the target app. Activation is what takes your keyboard focus, and what drags you across Spaces when the app lives on a different one (e.g. you're in a full-screen app and the agent is working on the desktop).

- **Accessibility first.** Reading UI trees, pressing buttons, setting values, typing (inserted at the caret), choosing menu items and scrolling all go through the Accessibility API.
- **Pointer events go to one window.** For anything accessibility can't reach (canvases, custom views, right/double clicks, drags, wheel scrolling), backseat builds events with `NSEvent.mouseEvent(windowNumber:)` and posts them straight to the owning process with `CGEventPostToPid`. WindowServer never routes them, so there's no click-to-activate. The embedded window number makes AppKit deliver them at exact window-relative points, even to covered or off-screen windows.
- **Keys go to one process.** Shortcuts and `type_text` with `method: "keys"` reach a background app without touching your keyboard focus.
- **Screenshots of single windows.** ScreenCaptureKit, falling back to CoreGraphics window capture for windows on another Space or off screen.
- **Windows on other Spaces.** Found through the app's focused and main windows plus remote-token lookup, because `AXWindows` only lists the current Space.
- **Safety net.** Some apps activate themselves anyway (Finder's Go to Folder, Safari's New Window). backseat hands focus straight back to the window you were in, and to its Space, through the WindowServer call window managers use: `NSRunningApplication.activate()` is silently refused for a background process since macOS 14. It keeps checking for a second in case the app's activation lands late.
- **Green outline.** The window the agent is working in gets a green outline, drawn only where that window is visible on your screen, ordered just above it, and left out of screenshots.
- **No beeps, no stray menus.** Input a background app would reject is never sent: ⌘ shortcuts are chosen from the menu bar (or refused when disabled), Return and Escape in a sheet or dialog press its default and Cancel buttons, and other keys there are refused (Save and Open panels run in a separate process, so keys sent to the app never reach them). Right-clicks that would open a context menu are refused unless forced.
- **Nothing hangs.** Every tool call times out after 60 seconds, and window capture falls back to CoreGraphics if ScreenCaptureKit stalls.

- **Scripting for what menus can't do.** Commands that act on the focused window (Bold, Save, New Folder, Close Window) are disabled in an app that isn't active. `run_script` sends Apple Events instead, which reach a background app without activating it, for any scriptable app. Scripts that activate apps or type and click through System Events are refused. It never sets off macOS's "wants access to control" dialog: before sending a script to an app, it asks macOS whether that's already allowed, without prompting, and refuses if not (unless the agent passes `allow_prompt`).
- **Fewer round trips.** `batch` runs several calls in one go (a step can use an element id found by an earlier step), `run_script` also takes zsh for files, `clipboard` reads and writes the clipboard, and `launch_app` opens URLs and documents in the background.
- **Seeing what the user sees.** `screenshot` with `as_seen` captures exactly the region of the user's screen where the agent's window is, outline included, and nothing outside it. It refuses windows the user can't see.
- **Replies say what happened.** `click` and `perform_action` report what changed afterwards: a menu that opened (with its items' ids), new windows, a sheet, a new title, changed contents, or no visible change. `find_elements` points a bare label (sidebar text, a button's caption) at the row or control to act on, and clicking the label acts on that. `set_value` confirms the whole value landed, and trees say how many characters they cut.
- **Waiting on real conditions.** `wait` returns when a web page has finished loading (with its title and URL), when a window stops changing, or when text appears or disappears.
- **Content before chrome.** `read_text` gives the page or document first, then sidebars, then window and browser controls, so `max_chars` is spent on what matters.
- **The agent's windows, not yours.** backseat tracks the windows an agent opened (and every window of an app it launched). Acting in any other window, or in the one you're working in, is refused unless the agent says you asked for that window (`user_window`). Apps that move tabs or documents between windows can't trick an agent into driving yours.
- **Agents know the layout.** `list_windows` says where each window is: on the user's Space or another (full-screen) one, minimized, app hidden, showing a dialog, a dialog window itself (an Open panel, an alert), or the user's focused window.

### Limitation

macOS has one active app per login session, and commands that act on the focused window (Bold, Save, New Folder) only run in the active app. backseat never takes the user's focus, so in an app that isn't scriptable and has no on-window control for such a command, it refuses rather than steal focus. Running every command in every app without touching the user's focus needs the agent's apps in their own session (a second macOS user logged in in the background, or a VM). backseat solves this with an agent session, below.

### Agent session

A second macOS user, left logged in in the background, has its own active app and keyboard focus. backseat runs there too, where commands that need focus (Bold, Save, New Folder) run in any app, and the user's session is never touched.

1. As an admin, create a standard user (System Settings > Users & Groups), log into it once, and switch back with fast user switching. Leave it logged in.
2. Put backseat where both users can reach it: `/Users/Shared/backseat/` (binary, `dev.backseat.agent.plist`, `install-agent.sh` from `scripts/agent-session/`).
3. In the agent user's session, run `zsh /Users/Shared/backseat/install-agent.sh <main user's uid>` and grant `/Users/Shared/backseat/backseat` Accessibility and Screen Recording there.
4. In the main user's Claude Code: `claude mcp add -s user backseat-agent -- /Users/Shared/backseat/backseat connect /Users/Shared/backseat/agent.sock`

`backseat listen` serves only the main user's uid (checked per connection) and starts one backseat per connection; `backseat connect` relays MCP over the socket unchanged.

## Skill

[`skills/backseat/SKILL.md`](skills/backseat/SKILL.md) teaches agents to work alongside you: open their own windows, check results in the accessibility tree, never repeat a send without checking, never take your focus. The installer adds it to Claude Code; with other tools, `npx skills add akshithio/backseat`. The same rules ship in the MCP server's instructions.

## Tools

`permissions` `list_apps` `list_windows` `launch_app` `get_ui_tree` `find_elements` `element_info` `perform_action` `set_value` `type_text` `press_key` `click` `scroll` `drag` `screenshot` `select_menu_item` `list_menu` `read_text` `close_window` `run_script` `clipboard` `batch` `wait`

## Build

```sh
swift build -c release
```

## Use with Claude Code

```sh
claude mcp add backseat -- "$(pwd)/.build/release/backseat"
```

The app that launches backseat (your terminal or MCP client) needs Accessibility and Screen Recording permission.

## Benchmark

```sh
python3 bench/compare.py
```

Runs 5 [mac-agent-bench](https://github.com/PrithviSeran/mac-agent-bench) tasks through Claude Code with backseat and through Codex with its computer use, judges each with the task's own checker, and counts how often the frontmost app changed and the pointer moved during the run. Run it while you're away from the Mac: Codex takes the real pointer and focus, and anything you do counts against the tool that's running. `--dry-run` checks the setup without running agents.

## Test

```sh
swift build && python3 Tests/e2e.py
```

This drives `BackseatFixture` through every tool and checks the fixture's own record of what happened. After every step it also checks that the fixture never became the active app. The fixture runs nearly transparent and off every display, so the suite is safe to run while you use the Mac.

A second pass opens the fixture on a regular desktop. If you're in a full-screen app at the time, that window is on another Space, and the pass checks it can be driven without pulling you over.
