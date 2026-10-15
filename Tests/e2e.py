#!/usr/bin/env python3
"""End-to-end test: drive BackseatFixture through backseat's MCP interface.

Every action is checked against the fixture's own state file. After each one
we also assert the fixture never became the active app: activation is what
steals the user's focus and drags them to another Space, so it must never
happen, for accessibility actions and pointer events alike.

The fixture runs off every display and nearly transparent, so this is safe to
run while you're using the Mac.

    swift build && python3 Tests/e2e.py              # everything that's invisible to the user
    swift build && python3 Tests/e2e.py --outline    # also check the green outline (shows briefly)
"""
import base64, json, os, plistlib, re, shutil, struct, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, ".build", "debug")


class MCP:
    def __init__(self, path):
        self.p = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.next_id = 0
        self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "e2e", "version": "0"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def send(self, msg):
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        while True:
            msg = json.loads(self.p.stdout.readline())
            if msg.get("id") == self.next_id:
                if "error" in msg:
                    raise RuntimeError(msg["error"])
                return msg["result"]

    def call(self, name, **args):
        r = self.request("tools/call", {"name": name, "arguments": args})
        text = "\n".join(c["text"] for c in r["content"] if c["type"] == "text")
        return r, text

    def ok(self, name, **args):
        r, text = self.call(name, **args)
        if r.get("isError"):
            raise AssertionError(f"{name} failed: {text}")
        return text

    def close(self):
        self.p.stdin.close()
        self.p.wait(timeout=5)


def jxa(expr):
    out = subprocess.run(["osascript", "-l", "JavaScript", "-e", "ObjC.import('AppKit');" + expr],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def make_bundle(tmp):
    app = os.path.join(tmp, "BackseatFixture.app")
    os.makedirs(os.path.join(app, "Contents", "MacOS"))
    shutil.copy(os.path.join(BIN, "BackseatFixture"), os.path.join(app, "Contents", "MacOS", "BackseatFixture"))
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump({"CFBundleExecutable": "BackseatFixture", "CFBundleIdentifier": "dev.backseat.fixture",
                       "CFBundleName": "BackseatFixture", "CFBundlePackageType": "APPL",
                       "NSPrincipalClass": "NSApplication"}, f)
    return app


def frame_of(line):
    m = re.search(r"@\((-?\d+),(-?\d+) (\d+)x(\d+)\)", line)
    return tuple(map(int, m.groups()))


def element(text, label):
    for line in text.splitlines():
        if f'"{label}"' in line:
            return line.split()[0], line
    raise AssertionError(f"no element labelled {label!r} in:\n{text}")


class Run:
    def __init__(self, mcp, mode):
        self.mcp, self.mode = mcp, mode
        self.tmp = tempfile.mkdtemp(prefix="backseat-e2e-")
        self.state_path = os.path.join(self.tmp, "state.json")
        self.passed, self.failed = [], []
        self.pid = self.wid = None

    def state(self):
        # The fixture rewrites this file as things change; retry a half-written read.
        for _ in range(20):
            try:
                with open(self.state_path) as f:
                    return json.load(f)
            except json.JSONDecodeError:
                time.sleep(0.02)
        with open(self.state_path) as f:
            return json.load(f)

    def eventually(self, pred, timeout=2.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if pred(self.state()):
                    return True
            except (FileNotFoundError, json.JSONDecodeError, KeyError):
                pass
            time.sleep(0.05)
        return False

    def check(self, name, fn, activates=False):
        """`activates`: the action makes the app activate itself on purpose (like
        Finder's New Finder Window); backseat must undo it, not prevent it."""
        name = f"[{self.mode}] {name}"
        try:
            active_before = self.state()["becameActive"]
            fn()
            if not activates:
                assert self.state()["becameActive"] == active_before, "fixture became the active app"
            front = jxa("$.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier")
            assert front != str(self.pid), "fixture is the user's frontmost app"
            self.passed.append(name)
            print(f"  ✓ {name}")
        except Exception as e:
            self.failed.append((name, e))
            print(f"  ✗ {name}: {e}")

    def launch(self, *flags):
        app = make_bundle(self.tmp)
        out = self.mcp.ok("launch_app", path=app, arguments=[self.state_path, *flags])
        self.pid = int(re.search(r"pid=(\d+)", out).group(1))
        assert self.eventually(lambda s: s.get("ready") and "onActiveSpace" in s), "fixture never became ready"
        text = self.mcp.ok("list_windows", pid=self.pid)
        self.wid = int(re.search(r'window (\d+) .*"Backseat Fixture"', text).group(1))

    def stop(self):
        if self.pid:
            subprocess.run(["kill", str(self.pid)])
            self.pid = None
        shutil.rmtree(self.tmp, ignore_errors=True)


def full_suite(r):
    m, wid, pid = r.mcp, r.wid, r.pid
    tree = ""

    def window_state():
        out = m.ok("list_windows", pid=r.pid)
        # The fixture is parked off-display and joins every desktop Space, but not a
        # full-screen app's Space: which one is right depends on where the user is.
        assert "but off every display" in out or "on another" in out, out
    r.check("list_windows says where the window is", window_state)

    def ui_tree():
        nonlocal tree
        tree = m.ok("get_ui_tree", window_id=wid)
        for label in ["Increment", "Name", "Keys", "Enable thing", "Level", "Click Pad", "Scroller", "count: 0"]:
            assert f'"{label}"' in tree, f"{label} missing from tree:\n{tree}"
    r.check("get_ui_tree", ui_tree)
    if not tree:
        return

    def find():
        text = m.ok("find_elements", window_id=wid, text="increment", role="button")
        assert "1 match" in text and "AXButton" in text, text
    r.check("find_elements", find)

    def ax_click():
        m.ok("click", element_id=element(tree, "Increment")[0])
        assert r.eventually(lambda s: s["count"] == 1), r.state()["count"]
    r.check("click element via accessibility", ax_click)

    def coord_press():
        bx, by, bw, bh = frame_of(element(tree, "Increment")[1])
        out = m.ok("click", window_id=wid, x=bx + bw // 2, y=by + bh // 2)
        assert "accessibility" in out, out
        assert r.eventually(lambda s: s["count"] == 2), r.state()["count"]
    r.check("click at a button's coordinates presses it", coord_press)

    px, py, _, _ = frame_of(element(tree, "Click Pad")[1])

    def pointer_click():
        out = m.ok("click", window_id=wid, x=px + 50, y=py + 60)
        assert "pointer events" in out, out
        assert r.eventually(lambda s: s["clicks"] == 1 and s["lastClick"] == [50, 60]), r.state()
    r.check("click on a custom view lands at the exact point", pointer_click)

    def double_click():
        m.ok("click", window_id=wid, x=px + 20, y=py + 20, count=2)
        assert r.eventually(lambda s: s["doubleClicks"] == 1 and s["lastClick"] == [20, 20]), r.state()
    r.check("double-click", double_click)

    def right_click():
        m.ok("click", window_id=wid, x=px + 30, y=py + 30, button="right")
        assert r.eventually(lambda s: s["rightClicks"] == 1), r.state()
    r.check("right-click", right_click)

    def right_click_menu_refused():
        # A text field has a context menu: opening it would pop a real menu up
        # and leave the app in menu tracking, answering nothing.
        fx, fy, fw, fh = frame_of(element(tree, "Name")[1])
        res, text = m.call("click", window_id=wid, x=fx + fw / 2, y=fy + fh / 2, button="right")
        assert res.get("isError") and "context menu" in text, text
    r.check("right-click that would open a context menu is refused", right_click_menu_refused)

    def drag():
        m.ok("drag", window_id=wid, from_x=px + 10, from_y=py + 10, to_x=px + 150, to_y=py + 120)
        assert r.eventually(lambda s: s["drag"] == [10, 10, 150, 120]), r.state()
    r.check("drag", drag)

    def set_value():
        m.ok("set_value", element_id=element(tree, "Name")[0], value="hello")
        assert r.eventually(lambda s: s["text"] == "hello"), r.state()
    r.check("set_value on text field", set_value)

    def type_ax():
        out = m.ok("type_text", element_id=element(tree, "Name")[0], text=" world")
        assert "accessibility" in out, out
        assert r.eventually(lambda s: s["text"] == "hello world"), r.state()
    r.check("type_text via accessibility appends", type_ax)

    def type_keys():
        out = m.ok("type_text", element_id=element(tree, "Keys")[0], text="abc", method="keys")
        assert "key events" in out, out
        assert r.eventually(lambda s: s["keysText"] == "abc"), r.state()
    r.check("type_text via per-process key events", type_keys)

    def press_delete():
        m.ok("press_key", element_id=element(tree, "Keys")[0], key="delete")
        assert r.eventually(lambda s: s["keysText"] == "ab"), r.state()
    r.check("press_key", press_delete)

    def checkbox():
        m.ok("click", element_id=element(tree, "Enable thing")[0])
        assert r.eventually(lambda s: s["checked"] is True), r.state()
    r.check("toggle checkbox", checkbox)

    def slider():
        m.ok("set_value", element_id=element(tree, "Level")[0], value="42")
        assert r.eventually(lambda s: abs(s["slider"] - 42) < 0.5), r.state()
    r.check("set_value on slider", slider)

    sx, sy, sw, sh = frame_of(element(tree, "Scroller")[1])

    def scroll_ax():
        out = m.ok("scroll", window_id=wid, x=sx + sw // 2, y=sy + sh // 2, dy=-300)
        assert "accessibility" in out, out
        assert r.eventually(lambda s: s["scrollY"] > 0), r.state()
    r.check("scroll via accessibility", scroll_ax)

    def scroll_wheel():
        before = r.state()["scrollY"]
        out = m.ok("scroll", window_id=wid, x=sx + sw // 2, y=sy + sh // 2, dy=-200, method="mouse")
        assert "pointer events" in out, out
        assert r.eventually(lambda s: s["scrollY"] >= before + 150), (before, r.state()["scrollY"])
    r.check("scroll via wheel events", scroll_wheel)

    def menu():
        m.ok("select_menu_item", pid=pid, path=["Fixture", "Reset Counter"])
        assert r.eventually(lambda s: s["menuResets"] == 1 and s["count"] == 0), r.state()
    r.check("select_menu_item", menu)

    def shortcut():
        m.ok("click", element_id=element(tree, "Increment")[0])
        assert r.eventually(lambda s: s["count"] == 1)
        m.ok("press_key", pid=pid, key="cmd+r")
        assert r.eventually(lambda s: s["menuResets"] == 2 and s["count"] == 0), r.state()
    r.check("keyboard shortcut reaches background app", shortcut)

    def wait():
        out = m.ok("wait", window_id=wid, text="count: 0", ms=2000)
        assert out.startswith("found"), out
    r.check("wait for text", wait)

    def info():
        out = m.ok("element_info", element_id=element(tree, "Increment")[0])
        assert 'AXRole: "AXButton"' in out and "actions: Press" in out, out
    r.check("element_info", info)

    def screenshot():
        res, caption = m.call("screenshot", window_id=wid)
        assert not res.get("isError"), caption
        img = next(c for c in res["content"] if c["type"] == "image")
        png = base64.b64decode(img["data"])
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        w, h = struct.unpack(">II", png[16:24])
        ww, wh = re.search(rf"window {wid} .*size (\d+)x(\d+)", m.ok("list_windows", pid=pid)).groups()
        assert (w, h) == (int(ww), int(wh)), f"image {w}x{h} vs window {ww}x{wh}"
    r.check("screenshot matches window size at scale 1", screenshot)

    def errors():
        res, text = m.call("click", element_id="e999999")
        assert res.get("isError") and "unknown element" in text, text
        res, text = m.call("press_key", pid=pid, key="hyper+banana")
        assert res.get("isError") and "unknown key" in text, text
    r.check("errors are reported, not thrown", errors)

    def list_apps():
        out = m.ok("list_apps")
        assert f"pid={pid}" in out, out
    r.check("list_apps", list_apps)

    def stable_ids():
        again = m.ok("get_ui_tree", window_id=wid)
        assert element(again, "Increment")[0] == element(tree, "Increment")[0], "element ids changed between calls"
    r.check("element ids are stable across calls", stable_ids)

    def batch():
        before = r.state()["count"]
        inc = element(tree, "Increment")[0]
        out = m.ok("click", element_ids=[inc, inc, inc])
        assert "Increment" in out, out
        assert r.eventually(lambda s: s["count"] == before + 3), (before, r.state()["count"])
    r.check("click several elements in one call", batch)

    def text():
        out = m.ok("read_text", window_id=wid)
        assert "‹Increment›" in out and "count:" in out, out
    r.check("read_text", text)

    def bare_label_row():
        # Like a sidebar: the text can't be pressed, its row is selected instead.
        out = m.ok("find_elements", window_id=wid, text="Beta")
        line = next(l for l in out.splitlines() if '"Beta"' in l)
        assert "→ select via" in line, out
        res = m.ok("click", element_id=line.split()[0])
        assert res.startswith("selected"), res
        assert r.eventually(lambda s: s.get("selectedRow") == "Beta"), r.state()
    r.check("find_elements points a bare label at its row, and click selects it", bare_label_row)

    def click_reports_change():
        out = m.ok("click", element_id=element(tree, "Increment")[0])
        assert "contents changed" in out, out
        out = m.ok("click", window_id=wid, x=px + 5, y=py + 5)
        assert "no visible change" in out, out
    r.check("click says what changed in the window", click_reports_change)

    def long_value_echo():
        value = "x" * 150 + "end"
        out = m.ok("set_value", element_id=element(tree, "Name")[0], value=value)
        assert "exactly the 153 characters given" in out, out
        tree_now = m.ok("get_ui_tree", window_id=wid)
        assert "(+" in tree_now and "chars)" in tree_now, "tree doesn't say the value was cut"
        m.ok("set_value", element_id=element(tree, "Name")[0], value="hello world")
    r.check("long values are confirmed, not cut off", long_value_echo)

    def waits():
        out = m.ok("wait", window_id=wid, until="settled", ms=4000)
        assert "stopped changing" in out, out
        out = m.ok("wait", pid=pid, text="no such text anywhere", until="gone", ms=1000)
        assert "is gone" in out, out
    r.check("wait until settled / gone", waits)

    def rows_cap():
        out = m.ok("get_ui_tree", window_id=wid, max_rows=1)
        assert "2 more rows" in out, out
    r.check("get_ui_tree max_rows", rows_cap)

    def text_order():
        out = m.ok("read_text", window_id=wid)
        assert "— window controls —" in out, out
        assert out.index("count:") < out.index("— window controls —"), out
    r.check("read_text puts window controls after content", text_order)

    def someone_elses_window():
        # A second backseat is a different agent: it didn't open the fixture, so
        # to it that's one of the user's windows. It may read it but not act in
        # it, unless it says the user asked for that window (user_window).
        other = MCP(os.path.join(BIN, "backseat"))
        try:
            clicks = r.state()["clicks"]
            res, text = other.call("click", window_id=wid, x=px + 5, y=py + 5)
            assert res.get("isError") and "one of the user's" in text, text
            assert r.state()["clicks"] == clicks, "it clicked anyway"
            assert "count:" in other.ok("read_text", window_id=wid)
            out = other.ok("click", window_id=wid, x=px + 5, y=py + 5, user_window=True)
            assert "clicked" in out, out
        finally:
            other.close()
    r.check("an agent never acts in a window it didn't open", someone_elses_window)

    def menus():
        out = m.ok("list_menu", pid=pid, path=["Fixture"])
        assert "Reset Counter" in out and "cmd+r" in out, out
    r.check("list_menu shows items and shortcuts", menus)

    def window_list_is_clean():
        out = m.ok("list_windows", pid=pid)
        assert out.count("window ") == 1 and "Backseat Fixture" in out, out
    r.check("list_windows shows only real windows", window_list_is_clean)

    def no_beep_shortcut():
        # A shortcut for a command that needs a focused window must never reach
        # the app as a key event (that's what makes it beep). backseat either
        # refuses it or chooses the menu item, which does nothing silently.
        before = r.state().get("keyDowns", 0)
        res, text = m.call("press_key", pid=pid, key="cmd+shift+d")
        assert "Needs Focus" in text, text
        time.sleep(0.3)
        assert r.state().get("keyDowns", 0) == before, "a key event was sent"
        print(f"      (ran: {r.state().get('needsFocusRan', 0)}; backseat said: {text[:90]})")
    r.check("shortcut for a focus-only command never sends a key", no_beep_shortcut, activates=True)

    def focus_only_command():
        # Like Bold or Save: AppKit only enables it while the app is active.
        # backseat never takes the user's focus, so it's refused, nothing sent.
        res, text = m.call("select_menu_item", pid=pid, path=["Fixture", "Focus Only"], window_id=wid)
        assert res.get("isError") and "never takes the user's focus" in text, text
        assert r.state().get("focusOnlyRan") is None, "the command ran"
    r.check("a command that needs the app active is refused, never by taking focus", focus_only_command)

    def enabled_shortcut_via_menu():
        before = r.state().get("keyDowns", 0)
        out = m.ok("press_key", pid=pid, key="cmd+r")
        assert "chose it from the menu" in out, out
        assert r.eventually(lambda s: s["menuResets"] >= 3), r.state()
        assert r.state().get("keyDowns", 0) == before, "sent a key event instead of choosing the menu item"
    r.check("enabled shortcut is chosen from the menu", enabled_shortcut_via_menu)

    def disabled_button():
        res, text = m.call("click", element_id=element(tree, "Unavailable")[0])
        assert res.get("isError") and "disabled" in text, text
    r.check("disabled button is refused", disabled_button)

    def sheet():
        m.ok("select_menu_item", pid=pid, path=["Fixture", "Show Sheet"])
        assert r.eventually(lambda s: s.get("sheetOpen") is True), r.state()
        res, text = m.call("click", element_id=element(tree, "Increment")[0])
        assert res.get("isError") and "sheet" in text, text
        t = m.ok("find_elements", window_id=wid, text="Close Sheet")
        m.ok("click", element_id=t.splitlines()[1].split()[0])
        assert r.eventually(lambda s: s.get("sheetOpen") is False), r.state()
    r.check("clicks behind an open sheet are refused", sheet)

    def keys_in_a_sheet():
        # Keys sent to a background app's sheet don't arrive (and Save panels
        # are another process), so the app beeps. Return and Escape press the
        # sheet's buttons through accessibility; anything else is refused.
        before = r.state().get("keyDowns", 0)
        m.ok("select_menu_item", pid=pid, path=["Fixture", "Show Sheet"])
        assert r.eventually(lambda s: s.get("sheetOpen") is True), r.state()
        res, text = m.call("press_key", window_id=wid, key="cmd+shift+g")
        assert res.get("isError") and "not sent" in text, text
        out = m.ok("press_key", window_id=wid, key="escape")
        assert "Cancel" in out, out
        assert r.eventually(lambda s: s.get("sheetOpen") is False and s.get("sheetCancels") == 1), r.state()
        m.ok("select_menu_item", pid=pid, path=["Fixture", "Show Sheet"])
        assert r.eventually(lambda s: s.get("sheetOpen") is True), r.state()
        out = m.ok("press_key", window_id=wid, key="return")
        assert "Close Sheet" in out, out
        assert r.eventually(lambda s: s.get("sheetOpen") is False), r.state()
        assert r.state().get("keyDowns", 0) == before, "a key event was sent"
    r.check("keys in a sheet press its buttons and never send key events", keys_in_a_sheet)

    def batching():
        before = r.state()["count"]
        out = m.ok("batch", steps=[
            {"tool": "find_elements", "args": {"window_id": wid, "text": "Increment", "role": "AXButton"}},
            {"tool": "click", "args": {"element_id": "$1"}},
            {"tool": "click", "args": {"element_id": "$1"}},
            {"tool": "read_text", "args": {"window_id": wid, "max_chars": 200}},
        ])
        assert out.count("\n") >= 3 and "FAILED" not in out, out
        assert r.eventually(lambda s: s["count"] == before + 2), r.state()
        out = m.ok("batch", steps=[{"tool": "click", "args": {"element_id": "e99999"}}, {"tool": "list_apps", "args": {}}])
        assert "FAILED" in out and "not run" in out, out
    r.check("batch runs steps in order, passes ids, stops on error", batching)

    def close():
        out = m.ok("close_window", window_id=wid)
        assert "closed" in out, out
    r.check("close_window", close)

    def scripts():
        out = m.ok("run_script", script="return 6 * 7")
        assert out.startswith("42"), out
        assert m.ok("run_script", script="(6 * 7).toString()", language="javascript").startswith("42")
        for bad in ['tell application "BackseatFixture" to activate',
                    'tell application "System Events" to keystroke "a"',
                    'Application("BackseatFixture").activate()']:
            res, text = m.call("run_script", script=bad, language="javascript" if "(" in bad else "applescript")
            assert res.get("isError") and "refused" in text, (bad, text)
    r.check("run_script runs scripts and refuses ones that take focus", scripts)

    def no_permission_dialog():
        # Nobody has allowed scripting the fixture, so sending it Apple Events
        # would pop macOS's "wants access to control" dialog. backseat asks macOS
        # without prompting and refuses instead. (If it was allowed, it just runs.)
        res, text = m.call("run_script", script='tell application "BackseatFixture" to get name')
        assert (res.get("isError") and "permission dialog" in text) or "BackseatFixture" in text, text
    r.check("run_script never sets off a permission dialog", no_permission_dialog)

    def shell_and_structure():
        assert m.ok("run_script", script="printf 'a\\nb'", language="shell") == "a\nb"
        out = m.ok("run_script", script='return {"x", {1, 2}}')
        assert out.startswith('{"x", {1, 2}}'), out
        res, text = m.call("run_script", script="open -a Calculator", language="shell")
        assert res.get("isError") and "-g" in text, text
    r.check("run_script: shell, structured results, foreground open refused", shell_and_structure)


    def quit_is_success():
        # The app exits before answering the press, which AX reports as an
        # error. An agent told "failed" would retry or give up; it worked.
        out = m.ok("select_menu_item", pid=r.pid, path=["BackseatFixture", "Quit"])
        assert "failed" not in out and "the app quit" in out, out
        assert r.eventually(lambda s: subprocess.run(["kill", "-0", str(r.pid)], capture_output=True).returncode != 0, timeout=3), "still running"
    r.check("a press that quits the app reports success", quit_is_success)


def other_space_suite(r):
    """The case that used to drag the user across Spaces: driving an app whose
    window is on a Space the user isn't looking at."""
    m, wid = r.mcp, r.wid
    tree = ""

    def window_state():
        # Only when the window really is on another Space; the detached
        # fallback is still on the user's Space as far as macOS is concerned.
        if r.state()["spaceMode"] != "opened on a Space the user isn't on":
            return
        out = m.ok("list_windows", pid=r.pid)
        assert "on another" in out, out
    r.check("list_windows says the window is elsewhere", window_state)

    def ui_tree():
        nonlocal tree
        tree = m.ok("get_ui_tree", window_id=wid)
        assert '"Increment"' in tree, tree
    r.check("get_ui_tree on another Space", ui_tree)
    if not tree:
        return

    def ax_click():
        m.ok("click", element_id=element(tree, "Increment")[0])
        assert r.eventually(lambda s: s["count"] == 1), r.state()["count"]
    r.check("accessibility click on another Space", ax_click)

    def pointer_click():
        px, py, _, _ = frame_of(element(tree, "Click Pad")[1])
        m.ok("click", window_id=wid, x=px + 40, y=py + 40)
        assert r.eventually(lambda s: s["lastClick"] == [40, 40]), r.state()
    r.check("pointer click on another Space", pointer_click)

    def typing():
        m.ok("type_text", element_id=element(tree, "Name")[0], text="hi")
        assert r.eventually(lambda s: s["text"] == "hi"), r.state()
    r.check("typing on another Space", typing)

    def screenshot():
        res, caption = m.call("screenshot", window_id=wid)
        assert not res.get("isError"), caption
    r.check("screenshot on another Space", screenshot)

    def as_seen_refused():
        if r.state()["spaceMode"] != "opened on a Space the user isn't on":
            return
        res, text = m.call("screenshot", window_id=wid, as_seen=True)
        assert res.get("isError") and "isn't visible" in text, text
    r.check("as_seen refuses a window the user can't see", as_seen_refused)

    def still_elsewhere():
        assert r.state()["onActiveSpace"] is False, "the window was moved to the user's Space"
    r.check("user was not pulled to the window's Space", still_elsewhere)

    def self_activation_undone():
        # Finder, Safari and TextEdit activate themselves when a command opens a
        # window. That drags the user to the app's Space; backseat has to put
        # them back in their own app, on their own Space, right away.
        user = jxa("$.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier")
        out = m.ok("select_menu_item", pid=r.pid, path=["Fixture", "Bring To Front"])
        assert r.eventually(lambda s: s["becameActive"] >= 1, timeout=2), "fixture never activated itself; test is moot"
        deadline = time.time() + 1.5
        while time.time() < deadline:
            front = jxa("$.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier")
            if front == user and r.state()["onActiveSpace"] is False:
                break
            time.sleep(0.05)
        assert front == user, f"focus stayed on pid {front}, user was in {user}; backseat said: {out[:120]}"
        # Only meaningful when the window really lives on another Space (the user
        # is in a full-screen app). A window detached from every Space joins the
        # current one when it activates, whatever backseat does.
        if r.state()["spaceMode"] == "opened on a Space the user isn't on":
            assert r.eventually(lambda s: s["onActiveSpace"] is False, timeout=1), "user was left on the app's Space"
        print(f"      (handed back in under {1.5 - (deadline - time.time()):.2f}s)")
    r.check("app that activates itself hands focus and Space back", self_activation_undone, activates=True)


def outline_suite(r):
    """Runs against a window that is really on screen: the outline is only
    drawn for those, and a background app's ordinary windows can't appear over
    a full-screen app, so it targets the fixture's non-activating probe panel."""
    m = r.mcp
    wid = int(re.search(r'window (\d+) .*"Outline Probe"', m.ok("list_windows", pid=r.pid)).group(1))

    def outline_fits():
        # The green outline is backseat's own window. Its stroke straddles the
        # target's edge, so it must be exactly the window's frame grown by half
        # the 3pt stroke: anything else is the outline not matching the window.
        found = m.ok("find_elements", window_id=wid, text="Probe", role="AXButton")
        m.ok("click", element_id=re.search(r"(e\d+) AXButton", found).group(1))
        def bounds(pid=None, number=None):
            ws = json.loads(jxa('ObjC.import("CoreGraphics"); JSON.stringify(ObjC.deepUnwrap(ObjC.castRefToObject('
                                '$.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0))).map(w => '
                                '[w.kCGWindowNumber, w.kCGWindowOwnerPID, w.kCGWindowIsOnscreen || false, w.kCGWindowBounds]))'))
            return [(n, b) for n, p, on, b in ws if (pid is None or p == pid) and (number is None or n == number) and on]
        assert r.eventually(lambda _: bounds(pid=m.p.pid), timeout=1), "no outline shown"
        (_, o), = bounds(pid=m.p.pid)
        (_, w), = bounds(number=wid)
        want = (w["X"] - 1.5, w["Y"] - 1.5, w["Width"] + 3, w["Height"] + 3)
        got = (o["X"], o["Y"], o["Width"], o["Height"])
        assert all(abs(a - b) <= 0.5 for a, b in zip(got, want)), f"outline {got} vs window {want}"
    r.check("green outline matches the window's frame", outline_fits)

    def new_window_stays_behind():
        # Apps order new windows in front even from the background. When one lands
        # on the user's Space, backseat raises the user's own window back above it.
        front = jxa("$.NSWorkspace.sharedWorkspace.frontmostApplication.localizedName")
        m.ok("select_menu_item", pid=r.pid, path=["Fixture", "New Window"])
        time.sleep(0.3)
        o = json.loads(jxa('ObjC.import("CoreGraphics"); JSON.stringify(ObjC.deepUnwrap(ObjC.castRefToObject('
                           '$.CGWindowListCopyWindowInfo(1, 0))).filter(w => w.kCGWindowLayer == 0).map(w => [w.kCGWindowOwnerName, w.kCGWindowName || ""]))'))
        extra = next((i for i, (n, t) in enumerate(o) if t == "Fixture Extra"), None)
        if extra is None:
            print("      (the new window opened on another Space: nothing landed on the user)")
            return
        user = next((i for i, (n, t) in enumerate(o) if n == front), None)
        assert user is not None and user < extra, f"new window is above the user's: {o[:5]}"
    r.check("a window an agent opens never lands on top of the user's", new_window_stays_behind)

    def as_seen():
        # The region of the user's screen where the window is, outline included,
        # and nothing beyond it.
        res, text = m.call("screenshot", window_id=wid, as_seen=True)
        assert not res.get("isError"), text
        px = re.search(r"(\d+)x(\d+) px", text)
        assert px, text
    r.check("as_seen captures the window's region of the screen", as_seen)


def main():
    mcp = MCP(os.path.join(BIN, "backseat"))
    print("permissions:\n  " + mcp.ok("permissions").replace("\n", "\n  "))
    print(f"{len(mcp.request('tools/list', {})['tools'])} tools\n")
    runs = []
    try:
        # Without --invisible the window isn't on every Space, so it opens on a
        # regular desktop. If the user is in a full-screen app right now, that
        # is a different Space from theirs: the case worth testing. It runs
        # first because it depends on where the user is at this moment.
        r = Run(mcp, "other Space")
        runs.append(r)
        r.launch("--other-space")
        assert r.eventually(lambda s: s["onActiveSpace"] is False), "couldn't get the fixture off the user's Space"
        print(f"  ({r.state()['spaceMode']})")
        other_space_suite(r)
        r.stop()

        if "--other-space-only" not in sys.argv:
            r = Run(mcp, "background")
            runs.append(r)
            r.launch("--invisible")
            full_suite(r)
            r.stop()

        if "--outline" in sys.argv:
            # Shows a small "Outline Probe" panel with a green outline in the
            # bottom-left corner for a couple of seconds, so it's opt-in.
            r = Run(mcp, "on screen")
            runs.append(r)
            r.launch("--onscreen")
            outline_suite(r)
            r.stop()
    finally:
        for r in runs:
            r.stop()
        mcp.close()

    passed = sum(len(r.passed) for r in runs)
    failed = [f for r in runs for f in r.failed]
    print(f"\n{passed} passed, {len(failed)} failed")
    for name, e in failed:
        print(f"  FAILED {name}: {e}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
