"use client";

import { useState } from "react";
import { BENCH, BENCH_TOTALS } from "@/lib/data";
import { Controls, usePlayer } from "./player";

type Mode = "tasks" | "total";
const SPEEDS = [1, 4, 10] as const;

function Bar({
  t,
  seconds,
  calls,
  scale,
  kind,
  marks,
}: {
  t: number;
  seconds: number;
  calls: number;
  scale: number;
  kind: "before" | "after";
  marks?: number[];
}) {
  const done = t >= seconds;
  const shown = Math.min(t, seconds);
  return (
    <div className="flex items-center gap-2">
      <span className="w-[3.2rem] shrink-0 text-[10px] tracking-[0.06em] text-muted">{kind}</span>
      <div className="relative h-4 min-w-0 flex-1">
        <div
          className={`absolute inset-y-0 left-0 rounded-[5px] border-[1.5px] border-ink ${kind === "before" ? "bar-before" : "bg-accent"}`}
          style={{ width: `${(shown / scale) * 100}%`, opacity: shown > 0 ? 1 : 0 }}
        >
          {marks?.map((m, i) =>
            m < shown ? (
              <span key={i} className="absolute inset-y-0 w-[1.5px] bg-ink" style={{ left: `${(m / shown) * 100}%` }} />
            ) : null,
          )}
        </div>
        <span
          className={`absolute top-1/2 -translate-y-1/2 whitespace-nowrap pl-2 text-[11px] tabular-nums ${done ? "text-ink" : "text-muted"}`}
          style={{ left: `${(shown / scale) * 100}%` }}
        >
          {done ? (
            <>
              <b>{seconds.toFixed(1)} s</b> · {calls} calls
            </>
          ) : shown > 0 ? (
            `${shown.toFixed(1)} s…`
          ) : null}
        </span>
      </div>
    </div>
  );
}

function delta(a: number, b: number, unit: string) {
  const d = b - a;
  const sign = d > 0 ? "+" : d < 0 ? "−" : "±";
  return `${sign}${Math.abs(d).toFixed(unit === "s" ? 1 : 0)}${unit === "s" ? " s" : ""}`;
}

export function BenchRace() {
  const [mode, setMode] = useState<Mode>("tasks");
  const [speed, setSpeed] = useState<(typeof SPEEDS)[number]>(10);
  const max = mode === "tasks" ? Math.max(...BENCH.map((b) => b.before.seconds)) : BENCH_TOTALS.before.seconds;
  const scale = Math.ceil(max * 1.28);
  const duration = Math.ceil(max) + 1;
  const player = usePlayer(duration, { speed, loop: false });
  const { t } = player;

  const cum = (key: "before" | "after") => {
    let s = 0;
    return BENCH.map((b) => (s += b[key].seconds)).slice(0, -1);
  };

  return (
    <div ref={player.ref} className="card p-4 sm:p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="display text-[24px] leading-tight sm:text-[28px]">The bench, replayed</h3>
        <span className="text-[11px] tracking-[0.06em] text-muted">mac-agent-bench · 5 tasks · a real Mac</span>
      </div>
      <p className="mt-2 max-w-[42rem] text-[12.5px] leading-[1.7] text-ink/80">
        The same agent on the same tasks, before and after backseat&apos;s latest tool changes. Hit play and each bar
        grows in agent wall time. <b>calls</b> are the agent&apos;s tool calls.
      </p>

      <div className="mt-5 flex flex-wrap items-center gap-2 text-[11px]">
        <div role="tablist" aria-label="View" className="flex gap-1">
          {(
            [
              ["tasks", "side by side"],
              ["total", "all 5 back to back"],
            ] as const
          ).map(([m, label]) => (
            <button
              key={m}
              role="tab"
              aria-selected={mode === m}
              type="button"
              onClick={() => {
                setMode(m);
                setSpeed(m === "total" ? 10 : 4);
                player.seek(0);
              }}
              className={`chip ${mode === m ? "bg-ink text-paper" : "bg-paper text-ink"}`}
            >
              {label}
            </button>
          ))}
        </div>
        <div className="ml-auto flex items-center gap-1" aria-label="Playback speed">
          {SPEEDS.map((s) => (
            <button
              key={s}
              type="button"
              aria-pressed={speed === s}
              onClick={() => setSpeed(s)}
              className={`chip ${speed === s ? "bg-sun text-ink" : "bg-paper text-muted"}`}
            >
              {s}×
            </button>
          ))}
        </div>
      </div>

      <div className="mt-5 space-y-5">
        {mode === "tasks" ? (
          BENCH.map((b) => {
            const slower = b.after.seconds > b.before.seconds;
            return (
              <div key={b.id}>
                <div className="mb-1.5 flex items-baseline justify-between gap-3 text-[12.5px]">
                  <span className="font-bold text-ink">{b.id}</span>
                  <span className={`tabular-nums text-[11px] ${slower ? "text-bad" : "text-ink/70"}`}>
                    {delta(b.before.seconds, b.after.seconds, "s")} · calls {b.before.calls} → {b.after.calls}
                    {slower ? " · slower" : ""}
                  </span>
                </div>
                <div className="space-y-1">
                  <Bar t={t} kind="before" seconds={b.before.seconds} calls={b.before.calls} scale={scale} />
                  <Bar t={t} kind="after" seconds={b.after.seconds} calls={b.after.calls} scale={scale} />
                </div>
              </div>
            );
          })
        ) : (
          <div>
            <div className="mb-1.5 flex items-baseline justify-between gap-3 text-[12.5px]">
              <span className="font-bold text-ink">all 5 tasks</span>
              <span className="tabular-nums text-[11px] text-ink/70">
                {delta(BENCH_TOTALS.before.seconds, BENCH_TOTALS.after.seconds, "s")} · calls{" "}
                {BENCH_TOTALS.before.calls} → {BENCH_TOTALS.after.calls}
              </span>
            </div>
            <div className="space-y-1">
              <Bar t={t} kind="before" seconds={BENCH_TOTALS.before.seconds} calls={BENCH_TOTALS.before.calls} scale={scale} marks={cum("before")} />
              <Bar t={t} kind="after" seconds={BENCH_TOTALS.after.seconds} calls={BENCH_TOTALS.after.calls} scale={scale} marks={cum("after")} />
            </div>
            <p className="label mt-3 text-muted">ticks mark where each task ends</p>
          </div>
        )}
      </div>

      <div className="mt-6">
        <Controls player={player} label="benchmark replay" format={(s) => `${Math.min(s, max).toFixed(1)} s @${speed}×`} step={0.1} />
      </div>
      <p className="mt-3 text-[11px] leading-[1.6] text-muted">
        Totals: {BENCH_TOTALS.before.calls} calls / {BENCH_TOTALS.before.seconds.toFixed(1)} s before,{" "}
        {BENCH_TOTALS.after.calls} calls / {BENCH_TOTALS.after.seconds.toFixed(1)} s after. grocery-edit got slower, and
        it stays on the chart.
      </p>
    </div>
  );
}
