#!/usr/bin/env python3
"""Live test: drive real browsers through backseat on a local test page.

Each browser gets one window of backseat's own, closed at the end. The page
reports every event it sees to a local server, so each check is verified from
the page's side, not backseat's. It waits until the user has been away from the
keyboard for a while and isn't in the browser under test, because these are
real windows of the user's own browsers.

    swift build -c release && python3 Tests/web.py            # Arc, Chrome, Safari
    python3 Tests/web.py Arc --now                           # one browser, don't wait for idle
"""
import http.server, json, os, re, socketserver, subprocess, sys, threading, time

os.environ["BACKSEAT_DEBUG"] = "1"  # backseat says on stderr why a browser route failed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from e2e import MCP, jxa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, ".build", "release", "backseat")
BROWSERS = {"Arc": "company.thebrowser.Browser", "Google Chrome": "com.google.Chrome", "Safari": "com.apple.Safari"}

PAGE = """<!doctype html><meta charset=utf-8><title>Backseat Web Test</title>
<style>body{font:16px system-ui;margin:20px} #scroller{height:120px;overflow:auto;border:1px solid #888}
#scroller div{height:2000px} .row{margin:10px 0}</style>
<h1>Backseat Web Test</h1>
<div class=row><a id=link href="/second">Second page</a></div>
<div class=row><button id=inc>Increment</button> <span id=count>count 0</span></div>
<div class=row><label>Plain field <input id=plain></label></div>
<div class=row id=react></div>
<div class=row><label><input type=checkbox id=check> Agree</label></div>
<div class=row><label>Fruit <select id=fruit><option>Apple</option><option>Banana</option><option>Cherry</option></select></label></div>
<div class=row><div id=scroller aria-label="Scroll box"><div>top</div></div></div>
<div style="height:1500px"></div><button id=far>Far button</button>
<script src="https://unpkg.com/react@18.3.1/umd/react.production.min.js"></script>
<script src="https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js"></script>
<script>
const log = (k, v) => fetch('/log', {method: 'POST', body: JSON.stringify({k, v})});
let n = 0;
inc.addEventListener('click', () => { n++; count.textContent = 'count ' + n; log('count', n); });
plain.addEventListener('input', () => log('plain', plain.value));
plain.addEventListener('keydown', e => { if (e.key === 'Enter') log('enter', plain.value); });
check.addEventListener('change', () => log('check', check.checked));
fruit.addEventListener('change', () => log('fruit', fruit.value));
scroller.addEventListener('scroll', () => log('scroll', scroller.scrollTop));
far.addEventListener('click', () => log('far', true));
// A React-controlled field: React only sees changes that fire real input events.
function Field() {
  const [v, setV] = React.useState('');
  return React.createElement('label', null, 'React field ',
    React.createElement('input', {id: 'reactfield', value: v, onChange: e => { setV(e.target.value); log('react', e.target.value); }}));
}
ReactDOM.createRoot(document.getElementById('react')).render(React.createElement(Field));
log('loaded', true);
</script>"""

SECOND = "<!doctype html><title>Second Page</title><h1>Second page</h1><script>fetch('/log',{method:'POST',body:JSON.stringify({k:'second',v:true})})</script>"

events = {}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (SECOND if self.path.startswith("/second") else PAGE).encode()
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        msg = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        events[msg["k"]] = msg["v"]
        self.send_response(204); self.end_headers()

    def log_message(self, *a):
        pass


def idle_seconds():
    out = subprocess.run(["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True).stdout
    return int(re.search(r'"HIDIdleTime" = (\d+)', out).group(1)) // 1_000_000_000


def frontmost():
    return jxa("$.NSWorkspace.sharedWorkspace.frontmostApplication.localizedName.js")


def wait_for_user_away(browser, now):
    while not now and (idle_seconds() < 120 or frontmost() == browser):
        time.sleep(15)
    if frontmost() == browser:
        raise SystemExit(f"the user is in {browser}; not testing it")


def eventually(pred, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pred():
            return True
        time.sleep(0.1)
    return False


def run(browser, url, now):
    wait_for_user_away(browser, now)
    m = MCP(BIN)
    passed, failed, wid, launched = [], [], None, False

    def call(tool, **a):
        r = m.request("tools/call", {"name": tool, "arguments": a})
        return r.get("isError", False), "\n".join(c["text"] for c in r["content"] if c["type"] == "text")

    last = []

    def ok(tool, **a):
        err, text = call(tool, **a)
        last.append(f"{tool} -> {text[:300]}")
        if err:
            raise AssertionError(f"{tool}: {text}")
        return text

    def el(text, role=None):
        args = {"window_id": wid, "text": text}
        if role:
            args["role"] = role
        out = ok("find_elements", **args)
        m_ = re.search(r"(e\d+) " + (role or r"AX\w+"), out)
        assert m_, out
        return m_.group(1)

    def check(name, fn):
        last.clear()
        try:
            fn(); passed.append(name); print(f"  ✓ {browser}: {name}")
        except Exception as e:
            failed.append((name, e)); print(f"  ✗ {browser}: {name}: {str(e)[:400]}")
            for line in last[-3:]:
                print(f"      {line}")

    try:
        running = subprocess.run(["pgrep", "-x", browser], capture_output=True).returncode == 0
        if not running:
            out = ok("launch_app", bundle_id=BROWSERS[browser])
            launched = True
            time.sleep(2)
        pid = int(subprocess.run(["pgrep", "-x", browser], capture_output=True, text=True).stdout.split()[0])
        before = set(re.findall(r"window (\d+) ", ok("list_windows", pid=pid)))
        out = ok("select_menu_item", pid=pid, path=["File", "New Window"])
        for _ in range(40):
            # Real windows only: Chrome also opens toolbar-sized helper windows.
            fresh = [w for w, h in re.findall(r"window (\d+) .* size \d+x(\d+)", ok("list_windows", pid=pid))
                     if w not in before and int(h) >= 200]
            if fresh:
                break
            time.sleep(0.25)
        assert fresh, out
        wid = int(fresh[0])
        print(f"{browser}: window {wid}")
        events.clear()

        def load():
            fields = ok("find_elements", window_id=wid, role="AXTextField")
            field = re.search(r"(e\d+) AXTextField", fields).group(1)
            ok("set_value", element_id=field, value=url)
            ok("press_key", window_id=wid, key="return", element_id=field)
            ok("wait", window_id=wid, until="loaded", ms=15000)
            assert eventually(lambda: events.get("loaded")), "page never reported loading"
        check("type an address and load it", load)

        def click_button():
            ok("click", element_id=el("Increment", "AXButton"), window_id=wid)
            assert eventually(lambda: events.get("count") == 1), events
        check("click a button", click_button)

        def plain_field():
            ok("set_value", element_id=el("Plain field", "AXTextField"), value="hello")
            assert eventually(lambda: events.get("plain") == "hello"), events
        check("set a text field", plain_field)

        def react_field():
            ok("set_value", element_id=el("React field", "AXTextField"), value="react ok")
            assert eventually(lambda: events.get("react") == "react ok"), events
        check("set a React-controlled field", react_field)

        def type_keys():
            ok("type_text", element_id=el("Plain field", "AXTextField"), text=" world")
            assert eventually(lambda: events.get("plain", "").endswith("world")), events
        check("type into a field", type_keys)

        def enter():
            ok("press_key", element_id=el("Plain field", "AXTextField"), key="return", window_id=wid)
            assert eventually(lambda: "enter" in events), events
        check("press Return in a field", enter)

        def checkbox():
            ok("click", element_id=el("Agree", "AXCheckBox"), window_id=wid)
            assert eventually(lambda: events.get("check") is True), events
        check("tick a checkbox", checkbox)

        def select():
            out = ok("find_elements", window_id=wid, text="Fruit")
            pop = re.search(r"(e\d+) AXPopUpButton", out) or re.search(r"(e\d+) AXComboBox", out)
            assert pop, out
            ok("set_value", element_id=pop.group(1), value="Cherry")
            assert eventually(lambda: events.get("fruit") == "Cherry"), events
        check("choose from a dropdown", select)

        def scroll_box():
            out = ok("find_elements", window_id=wid, text="top")
            e = re.search(r"(e\d+) ", out).group(1)
            ok("scroll", element_id=e, dy=-300, window_id=wid)
            assert eventually(lambda: (events.get("scroll") or 0) > 0), events
        check("scroll a box", scroll_box)

        def far_button():
            ok("click", element_id=el("Far button", "AXButton"), window_id=wid)
            assert eventually(lambda: events.get("far") is True), events
        check("click a button below the fold", far_button)

        def follow_link():
            ok("click", element_id=el("Second page", "AXLink"), window_id=wid)
            assert eventually(lambda: events.get("second") is True), events
        check("follow a link", follow_link)

        def navigate():
            events.pop("loaded", None)
            ok("launch_app", url=url, window_id=wid)
            ok("wait", window_id=wid, until="loaded", ms=15000)
            assert eventually(lambda: events.get("loaded")), events
        check("load a page in the same window", navigate)

        def focus_kept():
            assert frontmost() != browser, f"{browser} is frontmost"
        check("the browser never came to the front", focus_kept)
    finally:
        if wid:
            err, text = call("close_window", window_id=wid)
            if err:
                print(f"  ! couldn't close window {wid}: {text}")
        if launched:
            # Quit it the way the Dock does: needs no scripting permission.
            jxa(f'var a=$.NSRunningApplication.runningApplicationsWithBundleIdentifier("{BROWSERS[browser]}"); a.count>0 && a.objectAtIndex(0).terminate')
        m.close()
    return passed, failed


def main():
    now = "--now" in sys.argv
    picked = [b for b in BROWSERS if b in sys.argv] or list(BROWSERS)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_address[1]}/"
    total_p, total_f = 0, []
    # Test whichever browser the user isn't in; come back to the one they are.
    pending = list(picked)
    while pending:
        if not now and idle_seconds() < 120:
            time.sleep(15); continue
        ready = [b for b in pending if now or frontmost() != b]
        if not ready:
            time.sleep(15); continue
        b = ready[0]
        pending.remove(b)
        p, f = run(b, url, now)
        total_p += len(p); total_f += [(b, n, e) for n, e in f]
    print(f"\n{total_p} passed, {len(total_f)} failed")
    for b, n, e in total_f:
        print(f"  FAILED {b}: {n}: {str(e)[:300]}")
    sys.exit(1 if total_f else 0)


if __name__ == "__main__":
    main()
