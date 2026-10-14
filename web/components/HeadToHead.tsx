"use client";

import { useEffect, useRef, useState } from "react";
import { HEAD_TO_HEAD, type HeadToHead as Data } from "@/lib/data";

/**
 * backseat vs Codex computer use. Until HEAD_TO_HEAD in lib/data.ts is filled
 * in with real recordings or numbers, this renders nothing.
 */
export function HeadToHead() {
  // Shows up once there's a real head-to-head in lib/data.ts.
  return HEAD_TO_HEAD ? <Recorded data={HEAD_TO_HEAD} /> : null;
}


function Recorded({ data }: { data: Data }) {
  const a = useRef<HTMLVideoElement>(null);
  const b = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const [t, setT] = useState(0);
  const [duration, setDuration] = useState(0);

  useEffect(() => {
    const v = a.current ?? b.current;
    if (!v) return;
    const on = () => {
      setT(v.currentTime);
      setDuration(Math.max(a.current?.duration || 0, b.current?.duration || 0));
    };
    v.addEventListener("timeupdate", on);
    v.addEventListener("loadedmetadata", on);
    return () => {
      v.removeEventListener("timeupdate", on);
      v.removeEventListener("loadedmetadata", on);
    };
  }, []);

  const both = (fn: (v: HTMLVideoElement) => void) => [a.current, b.current].forEach((v) => v && fn(v));

  return (
    <div className="card p-4 sm:p-6">
      <h3 className="display text-[24px] leading-tight sm:text-[28px]">backseat vs Codex computer use</h3>
      {data.task ? <p className="mt-2 text-[12.5px] text-ink/80">{data.task}</p> : null}
      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        {[
          ["backseat", data.backseatVideo, a],
          ["Codex computer use", data.codexVideo, b],
        ].map(([name, src, ref]) => (
          <div key={name as string}>
            <div className="mb-2 text-[12px] font-bold">{name as string}</div>
            {src ? (
              <video
                ref={ref as React.RefObject<HTMLVideoElement>}
                src={src as string}
                muted
                playsInline
                className="aspect-video w-full rounded-[10px] border-2 border-ink bg-ink"
              />
            ) : (
              <div className="slot aspect-video rounded-[10px] border-2 border-dashed border-ink/40" />
            )}
          </div>
        ))}
      </div>
      {data.backseatVideo || data.codexVideo ? (
        <div className="mt-4 flex items-center gap-3">
          <button
            type="button"
            onClick={() => {
              if (playing) both((v) => v.pause());
              else both((v) => void v.play());
              setPlaying(!playing);
            }}
            className="sticker h-9 w-9 shrink-0 cursor-pointer bg-sun text-[12px] font-bold"
            aria-label={playing ? "Pause both" : "Play both"}
          >
            {playing ? "❚❚" : "▶"}
          </button>
          <input
            type="range"
            min={0}
            max={duration || 1}
            step={0.05}
            value={t}
            onChange={(e) => {
              const v = Number(e.target.value);
              both((el) => (el.currentTime = Math.min(v, el.duration || v)));
              setT(v);
            }}
            aria-label="Scrub both recordings"
            className="scrub min-w-0 flex-1"
            style={{ ["--p" as string]: `${duration ? (t / duration) * 100 : 0}%` }}
          />
        </div>
      ) : null}
      {data.rows.length ? (
        <table className="mt-5 w-full text-left text-[12px]">
          <thead className="text-muted">
            <tr>
              <th className="py-1 font-normal" />
              <th className="py-1 font-normal">backseat</th>
              <th className="py-1 font-normal">Codex</th>
            </tr>
          </thead>
          <tbody>
            {data.rows.map((r) => (
              <tr key={r.label} className="border-t border-rule">
                <td className="py-2">{r.label}</td>
                <td className="py-2 font-bold">{r.backseat}</td>
                <td className="py-2">{r.codex}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      {data.note ? <p className="mt-3 text-[11px] text-muted">{data.note}</p> : null}
    </div>
  );
}
