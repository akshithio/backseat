"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import type { Choreo } from "./choreo";
import { useStory } from "./engine";

export type Beat = [at: number, text: string];

/** A tall section with a sticky stage. Scroll progress drives `t`. */
export function Chapter({
  id,
  n,
  title,
  children,
  note,
  beats,
  choreo,
  Visual,
  tone = "plain",
  flip = false,
  era,
}: {
  id: string;
  n: string;
  title: ReactNode;
  children: ReactNode;
  note?: ReactNode;
  beats: Beat[];
  choreo: Choreo;
  Visual: (props: { t: number }) => ReactNode;
  tone?: "plain" | "bad" | "good";
  /** Picture on the left, text on the right (alternate acts). */
  flip?: boolean;
  /** A big tag on the picture: is this how it is today, or with backseat? */
  era?: "before" | "after";
}) {
  const { register } = useStory();
  const section = useRef<HTMLElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const [t, setT] = useState(0);

  useEffect(() => {
    if (!section.current || !stage.current) return;
    return register({
      kind: "scene",
      mode: "sticky",
      section: section.current,
      stage: stage.current,
      choreo,
      setT,
      lastT: -1,
    });
  }, [register, choreo]);

  let beat = beats[0];
  for (const b of beats) if (t >= b[0]) beat = b;

  const stickerTone =
    tone === "bad"
      ? "bg-codex text-paper"
      : tone === "good"
        ? "bg-go text-paper"
        : "bg-sun text-ink";

  return (
    <section ref={section} id={id} className="relative h-[135vh] pb-[6vh]" aria-labelledby={`${id}-title`}>
      {/* Pinned near the top at its own height, so the next act follows right after. */}
      <div
        className={`sticky top-[12vh] mx-auto flex max-w-[1120px] flex-col gap-5 px-4 sm:px-6 md:grid md:items-center md:gap-12 ${
          flip ? "md:grid-cols-[minmax(0,7fr)_minmax(0,5fr)]" : "md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]"
        }`}
      >
        <div className={`max-w-[30rem] ${flip ? "md:order-2" : ""}`}>
          <span
            className={`sticker inline-block px-2 py-0.5 text-[11px] font-bold uppercase tracking-[0.08em] ${stickerTone}`}
          >
            {n}
          </span>
          <h2
            id={`${id}-title`}
            className="display mt-3 text-[clamp(1.6rem,4.6vw,2.9rem)] leading-[1.02] text-ink"
          >
            {title}
          </h2>
          <div className="mt-3 text-[13px] leading-[1.7] text-ink/85 sm:text-[14px] md:mt-5">{children}</div>
          {note ? (
            <p className="label mt-4 hidden text-muted md:block">{note}</p>
          ) : null}
        </div>

        <figure className={`relative w-full ${flip ? "md:order-1" : ""}`}>
            {era ? (
              <span
                className={`mb-2.5 inline-block px-2.5 py-1 text-[12px] font-bold tracking-[0.06em] sm:text-[14px] ${
                  era === "before" ? "bg-ink text-paper" : "bg-accent text-white"
                }`}
              >
                {era === "before" ? "BEFORE" : "WITH BACKSEAT"}
              </span>
            ) : null}
          <div
            ref={stage}
            className="stage relative aspect-[16/10] w-full overflow-hidden rounded-[10px] border border-ink bg-paper"
          >
            <svg
              viewBox="0 0 160 100"
              className="absolute inset-0 h-full w-full font-sans"
              role="img"
              aria-label={beat[1]}
            >
              <Visual t={t} />
            </svg>
          </div>
          <figcaption className="mt-3 flex items-baseline gap-3">
            <span className="label min-h-[1.6em] text-ink" key={beat[1]}>
              <span className="beat-in inline-block">{beat[1]}</span>
            </span>
            <span className="ml-auto shrink-0 text-[10px] tracking-[0.08em] text-muted tabular-nums">
              {Math.round(t * 100).toString().padStart(2, "0")}%
            </span>
          </figcaption>
        </figure>
      </div>
    </section>
  );
}

/** x of the winding road, normalized, for progress f in 0..1. */
// Starts and ends under the stage's centre, swinging side to side between.
function road(f: number, wide: boolean, turns: number): [number, number] {
  const center = wide ? 0.7 : 0.5;
  const amp = wide ? 0.24 : 0.3;
  return [center + Math.sin(f * Math.PI * turns) * amp, f];
}

function roadPath(wide: boolean, turns: number) {
  const pts: string[] = [];
  for (let i = 0; i <= 80; i++) {
    const [x, y] = road(i / 80, wide, turns);
    pts.push(`${(x * 100).toFixed(2)} ${(y * 100).toFixed(2)}`);
  }
  return `M${pts.join(" L")}`;
}

/** The winding road between scenes. */
export function Connector({
  label,
  turns = 2,
  fadeOut = false,
  className = "h-[16vh]",
}: {
  label?: string;
  turns?: number;
  fadeOut?: boolean;
  className?: string;
}) {
  const { register } = useStory();
  const el = useRef<HTMLDivElement>(null);
  const ink = useRef<(SVGPathElement | null)[]>([]);

  useEffect(() => {
    if (!el.current) return;
    let lastF = -1;
    return register({
      kind: "path",
      el: el.current,
      fadeOut,
      at: (f, wide) => road(f, wide, turns),
      onProgress: (f) => {
        if (Math.abs(f - lastF) < 0.002) return;
        lastF = f;
        for (const p of ink.current) if (p) p.style.strokeDashoffset = String(1 - f);
      },
    });
  }, [register, turns, fadeOut]);

  return (
    <div ref={el} aria-hidden className={`relative mx-auto max-w-[1120px] px-4 sm:px-6 ${className}`}>
      {[false, true].map((wide) => {
        const d = roadPath(wide, turns);
        return (
          <svg
            key={String(wide)}
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            className={`absolute inset-0 h-full w-full ${wide ? "hidden md:block" : "md:hidden"}`}
          >
            <path d={d} className="road-bed" vectorEffect="non-scaling-stroke" fill="none" />
            <path
              d={d}
              ref={(p) => {
                ink.current[wide ? 1 : 0] = p;
              }}
              pathLength={1}
              className="road-ink"
              vectorEffect="non-scaling-stroke"
              fill="none"
              style={{ strokeDasharray: "1 1", strokeDashoffset: 1 }}
            />
          </svg>
        );
      })}
      {label ? (
        <p className="label absolute left-4 top-1/2 max-w-[11rem] -translate-y-1/2 text-muted sm:left-6 md:left-[8%]">
          {label}
        </p>
      ) : null}
    </div>
  );
}

/** Registers the hero as a time-driven scene. */
export function HeroStage({ choreo, children, className }: { choreo: Choreo; children: ReactNode; className?: string }) {
  const { register } = useStory();
  const el = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!el.current) return;
    return register({ kind: "scene", mode: "time", section: el.current, stage: el.current, choreo, lastT: 0 });
  }, [register, choreo]);
  return (
    <div ref={el} className={className}>
      {children}
    </div>
  );
}
