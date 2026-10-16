---
name: backseat
description: How to operate Mac apps with the backseat MCP tools while the user keeps using their Mac. Use whenever a task means doing something in a Mac app on the user's behalf, or calls backseat's tools (list_windows, click, type_text, select_menu_item, run_script and the rest).
---

# Using backseat

The user is using this Mac at the same time as you. Finish the task without them noticing anything but the result: their pointer, keyboard, windows and Space stay theirs.

## Work in a window of your own

- Before acting in an app, call `list_windows` with its pid. The window marked "the user's focused window" is theirs, and so is every window you didn't open.
- Open your own window for the task, even in an app the user has open: `select_menu_item` with the app's New Window command, or `launch_app` with a `url` or file. Take the new window's id from the reply and pass that `window_id` to every call.
- If the user is in that app right now, don't open a window there: backseat refuses, because the new window would take their focus. Use a window you already have, or another app.
- One window per task, reused. Every window you open lands on the user's screen. Do the next step in the window you have (in a browser, its own address field and links), not in a new window per step. backseat refuses to open more than 3 per app until you close some.
- Keep checking it's still yours. Some apps share tabs or documents between windows, so a window can start showing something you didn't open, and the user may switch into it. If either happens, stop using it, open a fresh window and carry on there. Never get back on track by navigating some other window.
- backseat refuses to act in windows you didn't open. Pass `user_window: true` only when the user explicitly asked you to use that particular window.
- When you're done, close every window you opened (`list_windows` marks them "yours", including ones a `batch` opened), and quit apps you launched that weren't already running.

## Act through the accessibility tree

- Don't write your own JavaScript for web pages, and never read cookies, tokens or other session data.
- Do the task on the user's own Mac, in their own apps, where they're already signed in. Don't move it to another browser (the built-in browser pane or a headless one) or hand it back to the user because one route failed; try another backseat route, and only if none works, say exactly what's blocked.

- Find things with `find_elements` (text and/or role) and act on element ids: `click`, `set_value`, `type_text`, `select_menu_item`. Use coordinates only for things that aren't in the tree.
- Check results with `read_text` or `get_ui_tree`; they always show the current state. A screenshot of a window the user can't see may be out of date, so don't use it to judge whether something worked.
- Use `wait` (`until: "loaded"`, `"settled"`, or `text`) instead of sleeping, and `batch` to run several steps in one call.

## Never repeat something that may already have worked

- Fields and pages can take a moment to update. After typing or pressing, `wait` until settled and read again before deciding it failed.
- Before repeating anything with side effects (send, submit, post, buy, delete, move), confirm it didn't already happen: look for the sent message, the confirmation, the item's new state.

## Never take the user's focus

- Never activate an app, and never type or click through System Events. backseat refuses these.
- If a reply says an app brought itself to the front and focus went back to the user, carry on. Prefer a different route over repeating the step that caused it.
- `run_script` only reaches apps the user has already allowed scripting. If it refuses, use the accessibility tools for that app.

## Be persistent, quietly

- If a route fails, try a different one (another element, the menu command instead of a button) rather than the same call again.
- Tell the user the outcome in a sentence or two. Don't narrate backseat's mechanics (Spaces, stale screenshots, focus hand-backs) unless they changed the result.
