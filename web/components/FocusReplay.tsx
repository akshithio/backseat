"use client";

import { FOCUS } from "@/lib/data";
import { Chip, MenuBar, Typing, Wallpaper, Win } from "./story/mac";
import { ramp } from "./story/choreo";
import { Controls, usePlayer } from "./player";

// Illustrative timeline (seconds). The only measured duration here is the
// 3–23 ms hand-back, which is labelled as such.
const DURATION = 8;
const SENT = 2.0;
const ACTIVATES = 2.4;
const HANDED_BACK = 2.62; // drawn long enough to see; real value is FOCUS.minMs–maxMs

const ESSAY = "my essay, in full screen, minding my own business. the agent is tidying Downloads somewhere else.";

function typedAt(t: number, stopAt = Infinity) {
  const s = Math.min(t, stopAt);
  return ESSAY.slice(0, Math.floor(Math.min(1, s / 6.5) * ESSAY.length));
}

function FullScreenDoc({ text, caret }: { text: string; caret: boolean }) {
  return (
    <g>
      <rect width="160" height="90" fill="#ecebe7" />
      <rect x="31" y="11" width="100" height="90" fill="var(--color-ink)" opacity="0.12" />
      <rect x="30" y="10" width="100" height="90" fill="#ffffff" stroke="var(--color-ink)" strokeWidth="0.3" />
      <text x="36" y="19" fontSize="3.6" fontWeight="700" fill="var(--color-ink)">On sharing</text>
      <Typing x={36} y={27} text={text} cols={50} caret={caret} />
    </g>
  );
}

function Lane({ t, mode }: { t: number; mode: "before" | "after" }) {
  const before = mode === "before";
  const slide = before ? ramp(t, ACTIVATES, ACTIVATES + 0.45) : 0;
  const onDesktop = before && t >= ACTIVATES;
  const flash = !before && t >= ACTIVATES && t < HANDED_BACK;
  const back = !before && t >= HANDED_BACK;
  const text = typedAt(t, before ? ACTIVATES : Infinity);
  const sent = t >= SENT;

  return (
    <svg viewBox="0 0 160 90" className="block h-auto w-full font-sans" role="img"
      aria-label={before ? "Before the fix: you are pulled to the desktop and focus stays on Finder." : `With backseat: Finder jumps forward, focus returns within ${FOCUS.minMs} to ${FOCUS.maxMs} ms and your Space stays put.`}>
      <defs>
        <clipPath id={`lane-${mode}`}>
          <rect width="160" height="90" />
        </clipPath>
      </defs>
      <g clipPath={`url(#lane-${mode})`}>
        <g transform={`translate(${slide * 160} 0)`}>
          <g transform="translate(-160 0)">
            <Wallpaper />
            <Win x={20} y={12} w={120} h={60} title="Finder" active={onDesktop}>
              <g transform="translate(26 6)">
                <rect width="68" height="20" rx="1.4" fill="#ffffff" stroke="var(--color-ink)" strokeWidth="0.4" />
                <text x="4" y="6" fontSize="2.4" fontWeight="700" fill="var(--color-ink)">Go to the folder:</text>
                <rect x="4" y="9" width="60" height="6" rx="1" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.35" />
                <text x="5.5" y="13" fontSize="2.6" fill="var(--color-ink)">~/Downloads/</text>
              </g>
            </Win>
          </g>
          <FullScreenDoc text={text} caret={!onDesktop && !flash} />
        </g>

        {flash ? <rect x="0.6" y="0.6" width="158.8" height="88.8" fill="none" stroke="var(--color-bad)" strokeWidth="1.2" /> : null}
        <MenuBar app={onDesktop || flash ? "Finder" : "Pages"} space={onDesktop ? 1 : 2} />

        <Chip x={4} y={9} o={sent && t < ACTIVATES ? 1 : 0}>
          {"agent → Finder: Go to Folder"}
        </Chip>
        <Chip x={4} y={81} tone={onDesktop ? "bad" : before ? "plain" : "good"}>
          {onDesktop ? "space 2 → 1" : before ? "space 2" : "space 2 · unchanged"}
        </Chip>
        <Chip x={156} y={81} anchor="end" tone={onDesktop || flash ? "bad" : back ? "good" : "plain"}>
          {onDesktop ? "focus: Finder" : flash ? "Finder jumped forward" : back ? `focus back in ${FOCUS.minMs}–${FOCUS.maxMs} ms` : "focus: you"}
        </Chip>
        <Chip x={156} y={9} anchor="end" tone="bad" o={before ? ramp(t, 4, 4.3) : 0}>
          focus never came back
        </Chip>
      </g>
    </svg>
  );
}

function Track({ t, mode }: { t: number; mode: "before" | "after" }) {
  const pct = (s: number) => `${(s / DURATION) * 100}%`;
  return (
    <div className="relative mt-3 h-6">
      <div className="absolute inset-x-0 top-2 h-2.5 overflow-hidden rounded-full border border-ink bg-go/70">
        {mode === "before" ? (
          <div className="absolute inset-y-0 right-0 bg-bad" style={{ left: pct(ACTIVATES) }} />
        ) : (
          <div className="absolute inset-y-0 w-[3px] bg-bad" style={{ left: pct(ACTIVATES) }} />
        )}
      </div>
      <div className="absolute top-0 h-6 w-[2px] -translate-x-1/2 bg-ink" style={{ left: pct(t) }} />
    </div>
  );
}

export function FocusReplay() {
  const player = usePlayer(DURATION, { speed: 1 });
  const { t } = player;

  return (
    <div ref={player.ref} className="card p-4 sm:p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="display text-[24px] leading-tight sm:text-[28px]">Focus, before and after</h3>
        <span className="text-[11px] tracking-[0.06em] text-muted">a background Finder &ldquo;Go to Folder&rdquo;</span>
      </div>

      <div className="mt-5 grid gap-6 md:grid-cols-2">
        {(["before", "after"] as const).map((mode) => (
          <div key={mode}>
            <div className="mb-2 flex items-center gap-2 text-[12px]">
              <span className={`sticker px-2 py-0.5 font-bold ${mode === "before" ? "bg-bad text-paper" : "bg-go text-paper"}`}>
                {mode === "before" ? "before the fix" : "backseat now"}
              </span>
            </div>
            <div className="overflow-hidden rounded-[10px] border-2 border-ink">
              <Lane t={t} mode={mode} />
            </div>
            <Track t={t} mode={mode} />
            <p className="mt-2 text-[12px] leading-[1.65] text-ink/80">
              {mode === "before"
                ? "Pulled out of the full-screen app to the desktop. Focus never came back."
                : `Finder still jumps forward on its own. backseat hands focus back within ${FOCUS.minMs}–${FOCUS.maxMs} ms (measured over ${FOCUS.activations} activations), and your Space never changes.`}
            </p>
          </div>
        ))}
      </div>

      <div className="mt-6">
        <Controls player={player} label="focus replay" format={(s) => `${s.toFixed(1)} s`} />
      </div>
      <p className="mt-3 text-[11px] leading-[1.6] text-muted">
        <span className="inline-block h-2 w-2 rounded-full bg-go align-middle" /> focus on your app &nbsp;
        <span className="inline-block h-2 w-2 rounded-full bg-bad align-middle" /> focus elsewhere
      </p>
    </div>
  );
}

