"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useReducedMotion } from "./story/engine";

/**
 * A tiny timeline: play/pause, scrub, optional loop.
 * Starts playing when scrolled into view (unless the reader prefers reduced
 * motion, in which case it starts paused on the final frame).
 */
export function usePlayer(duration: number, { speed = 1, loop = true } = {}) {
  const reduced = useReducedMotion();
  const [t, setT] = useState(0);
  const [playing, setPlaying] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const started = useRef(false);
  const tRef = useRef(0);
  tRef.current = t;

  useEffect(() => {
    if (reduced && !started.current) setT(duration);
  }, [reduced, duration]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting && !started.current && !reduced) {
          started.current = true;
          setPlaying(true);
        }
        if (!e.isIntersecting) setPlaying(false);
      },
      { threshold: 0.35 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [reduced]);

  useEffect(() => {
    if (!playing) return;
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = ((now - last) / 1000) * speed;
      last = now;
      let next = tRef.current + dt;
      if (next >= duration) {
        if (loop) next = 0;
        else {
          next = duration;
          setPlaying(false);
        }
      }
      tRef.current = next;
      setT(next);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, duration, loop]);

  const toggle = useCallback(() => {
    started.current = true;
    setPlaying((p) => {
      if (!p && tRef.current >= duration - 0.01) setT(0);
      return !p;
    });
  }, [duration]);

  const seek = useCallback((v: number) => {
    started.current = true;
    setPlaying(false);
    setT(v);
  }, []);

  return { t, playing, toggle, seek, ref, duration };
}

export function Controls({
  player,
  label,
  format,
  step = 0.01,
}: {
  player: ReturnType<typeof usePlayer>;
  label: string;
  format: (t: number) => string;
  step?: number;
}) {
  const { t, playing, toggle, seek, duration } = player;
  return (
    <div className="flex items-center gap-3">
      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? `Pause ${label}` : `Play ${label}`}
        className="sticker grid h-9 w-9 shrink-0 cursor-pointer place-items-center bg-sun text-ink transition-colors hover:bg-ink hover:text-paper"
      >
        {playing ? (
          <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden>
            <rect x="2" y="1.5" width="3" height="9" rx="0.6" fill="currentColor" />
            <rect x="7" y="1.5" width="3" height="9" rx="0.6" fill="currentColor" />
          </svg>
        ) : (
          <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden>
            <path d="M3 1.5v9l7.5-4.5Z" fill="currentColor" />
          </svg>
        )}
      </button>
      <input
        type="range"
        min={0}
        max={duration}
        step={step}
        value={t}
        onChange={(e) => seek(Number(e.target.value))}
        aria-label={`Scrub ${label}`}
        aria-valuetext={format(t)}
        className="scrub min-w-0 flex-1"
        style={{ ["--p" as string]: `${(t / duration) * 100}%` }}
      />
      <span className="w-[5.5rem] shrink-0 text-right text-[11px] tabular-nums text-muted">{format(t)}</span>
    </div>
  );
}
