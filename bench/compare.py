#!/usr/bin/env python3
"""backseat vs Codex computer use, on the same mac-agent-bench tasks.

    python3 bench/compare.py                  # 5 tasks x 1 trial, both tools
    python3 bench/compare.py --runs 3         # more trials
    python3 bench/compare.py --only codex     # one side
    python3 bench/compare.py --dry-run        # setup/check/teardown only, no agents

Each trial: the task's setup.sh, then the agent, then its check.sh (judges the
real outcome) and teardown.sh. A monitor samples the frontmost app and the
pointer at 5 Hz while the agent runs: switches and pointer moves are what the
user would have felt. Run it while you're away from the Mac: Codex moves the
real pointer and takes focus, and any movement of yours would count against
whichever tool is running.

- backseat: Claude Code (`claude -p`) with only backseat's MCP tools, exactly
  mac-agent-bench's own method.
- codex: `codex exec` with its computer use. Its shell is read-only, so the
  work has to go through computer use, as Claude's goes through backseat.
"""
import argparse, ctypes, json, os, subprocess, sys, tempfile, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BENCH = HERE / ".mac-agent-bench"
BENCH_REPO = "https://github.com/PrithviSeran/mac-agent-bench"
BENCH_COMMIT = "d5cda36"
TASKS = ["01", "15", "16", "17", "19"]


def fetch_bench():
    if not (BENCH / "run.py").exists():
        subprocess.run(["git", "clone", "--quiet", BENCH_REPO, str(BENCH)], check=True)
    subprocess.run(["git", "-C", str(BENCH), "checkout", "--quiet", BENCH_COMMIT], check=True)
    sys.path.insert(0, str(BENCH))
    import run as bench  # mac-agent-bench's runner: ScreenMonitor, run_script, run_task
    return bench


class CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]


_cg = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
_cg.CGEventCreate.restype = ctypes.c_void_p
_cg.CGEventCreate.argtypes = [ctypes.c_void_p]
_cg.CGEventGetLocation.restype = CGPoint
_cg.CGEventGetLocation.argtypes = [ctypes.c_void_p]
_cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
_cf.CFRelease.argtypes = [ctypes.c_void_p]


def _create(_none):
    return _cg.CGEventCreate(None)


def _location(event):
    p = _cg.CGEventGetLocation(event)
    _cf.CFRelease(event)
    return p


def monitor(bench):
    # The bench reads the pointer through PyObjC's Quartz; read it through
    # CoreGraphics directly so it works without PyObjC installed.
    m = bench.ScreenMonitor()
    m._cg = (_create, _location)
    return m


def clipboard():
    return subprocess.run(["pbpaste"], capture_output=True).stdout


def run_codex(bench, task_dir, timeout, transcript):
    prompt = (task_dir / "prompt.txt").read_text().strip()
    result = {"task": task_dir.name, "started": datetime.now().isoformat(timespec="seconds")}
    rc, out = bench.run_script(task_dir / "setup.sh")
    if rc != 0:
        result.update(status="setup-failed", success=False, detail=out)
        return result
    work = tempfile.mkdtemp(prefix="codex-bench-")
    cmd = ["codex", "exec", "--json", "--ephemeral", "--skip-git-repo-check", "-C", work,
           "-s", "read-only", "-c", 'approval_policy="never"',
           prompt + "\n\nDo this on the Mac with computer use."]
    m = monitor(bench)
    m.start()
    t0 = time.time()
    status, stdout = "completed", ""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        stdout = p.stdout
        if p.returncode != 0:
            status = "agent-error"
            result["agent_output"] = (p.stdout[-1500:] + p.stderr[-1500:])
    except subprocess.TimeoutExpired as e:
        status = "timeout"
        stdout = e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
    wall = round(time.time() - t0, 1)
    m.stop()
    transcript.write_text(stdout)

    tools, last = [], ""
    for line in stdout.splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = ev.get("item") or {}
        if ev.get("type") == "item.completed":
            kind = item.get("type", "")
            if kind in ("mcp_tool_call", "command_execution", "computer_call", "function_call"):
                tools.append(item.get("tool") or item.get("name") or kind)
            if kind == "agent_message":
                last = item.get("text", "")
    check_rc, check_out = bench.run_script(task_dir / "check.sh")
    bench.run_script(task_dir / "teardown.sh")
    result.update(
        status=status, success=check_rc == 0, check=check_out, wall_s=wall,
        front_app_at_start=m.baseline, focus_switches=len(m.switches), focus_apps=m.switches[:20],
        cursor_moves=m.cursor_moves, cursor_travel_px=round(m.cursor_px),
        tool_calls=len(tools), tools_used=sorted(set(map(str, tools))), agent_says=last[:500],
    )
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--tasks", default=",".join(TASKS))
    ap.add_argument("--only", choices=["backseat", "codex"])
    ap.add_argument("--model", default="sonnet", help="Claude model for the backseat side")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    bench = fetch_bench()
    binary = ROOT / ".build" / "release" / "backseat"
    if args.only != "codex" and not args.dry_run:
        subprocess.run(["swift", "build", "-c", "release", "--package-path", str(ROOT)], check=True,
                       stdout=subprocess.DEVNULL)
    adapter = {"mcp": {"mcpServers": {"backseat": {"command": str(binary)}}}, "allowedTools": ["mcp__backseat"]}

    results = HERE / "results"
    results.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    mcp_file = results / ".mcp-backseat.json"
    mcp_file.write_text(json.dumps(adapter["mcp"]))
    out_path = results / f"{stamp}.jsonl"

    prefixes = [p.strip() for p in args.tasks.split(",") if p.strip()]
    tasks = sorted(d for d in (BENCH / "tasks").iterdir() if d.is_dir() and any(d.name.startswith(p) for p in prefixes))
    sides = [args.only] if args.only else ["backseat", "codex"]
    saved_clip = clipboard()
    rows = []
    try:
        with out_path.open("a") as out:
            for task in tasks:
                for side in sides:
                    for trial in range(args.runs):
                        print(f"▶ {side:8} {task.name} [{trial + 1}/{args.runs}]", flush=True)
                        t = results / f"{stamp}-{side}-{task.name}-t{trial + 1}.jsonl"
                        if args.dry_run:
                            rc, o = bench.run_script(task / "setup.sh")
                            crc, co = bench.run_script(task / "check.sh")
                            bench.run_script(task / "teardown.sh")
                            r = {"task": task.name, "status": "dry-run", "success": False,
                                 "setup_rc": rc, "check": co[:200], "check_rc": crc}
                        elif side == "codex":
                            r = run_codex(bench, task, args.timeout, t)
                        else:
                            r = bench.run_task(task, adapter, mcp_file, args.model, args.timeout, transcript=t)
                        r.update(tool=side, trial=trial + 1)
                        out.write(json.dumps(r) + "\n")
                        out.flush()
                        rows.append(r)
                        print(f"  {'✓' if r['success'] else '✗'} {r['status']}  wall={r.get('wall_s', '-')}s"
                              f"  calls={r.get('tool_calls', '-')}  focus switches={r.get('focus_switches', '-')}"
                              f"  pointer moves={r.get('cursor_moves', '-')}"
                              f"  {'' if r['success'] else (r.get('check') or r.get('detail') or '')[:120]}", flush=True)
    finally:
        # Tasks put their own text on the clipboard; give the user theirs back.
        subprocess.run(["pbcopy"], input=saved_clip)

    print(f"\n{'tool':10}{'passed':>8}{'avg s':>8}{'calls':>7}{'focus':>7}{'pointer':>9}")
    for side in sides:
        rs = [r for r in rows if r["tool"] == side]
        if not rs:
            continue
        walls = [r["wall_s"] for r in rs if r.get("wall_s")]
        avg = f"{sum(walls) / len(walls):.0f}" if walls else "-"
        print(f"{side:10}{sum(r['success'] for r in rs):>5}/{len(rs):<2}{avg:>8}"
              f"{sum(r.get('tool_calls') or 0 for r in rs):>7}{sum(r.get('focus_switches') or 0 for r in rs):>7}"
              f"{sum(r.get('cursor_moves') or 0 for r in rs):>9}")
    print(f"\nresults → {out_path}")


if __name__ == "__main__":
    main()
