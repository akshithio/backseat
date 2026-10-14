"use client";

import { useState } from "react";

const LINES: { cmd?: string; comment?: string }[] = [
  { cmd: "curl -fsSL https://backseat.akshith.io/install.sh | sh" },
];

export function Install() {
  const [copied, setCopied] = useState(false);
  const text = LINES.filter((l) => l.cmd).map((l) => l.cmd).join("\n");

  return (
    <div className="terminal relative overflow-hidden rounded-[14px] border-2 border-ink bg-[#1c1c1b] text-[#f5f5f3]">
      <div className="flex items-center gap-1.5 border-b border-white/10 px-4 py-2.5">
        {["#ff6159", "#ffbd2e", "#28c840"].map((c) => (
          <span key={c} className="h-2.5 w-2.5 rounded-full" style={{ background: c }} />
        ))}
        <span className="ml-3 text-[11px] text-white/45">~</span>
        <button
          type="button"
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(text);
              setCopied(true);
              setTimeout(() => setCopied(false), 1600);
            } catch {
              /* clipboard blocked; the text is selectable */
            }
          }}
          className="ml-auto cursor-pointer rounded-md border border-white/20 px-2 py-0.5 text-[11px] text-white/80 transition-colors hover:bg-white/10"
        >
          {copied ? "copied" : "copy"}
        </button>
      </div>
      <pre className="overflow-x-auto px-4 py-4 text-[12px] leading-[1.9] sm:text-[13px]">
        {LINES.map((l, i) =>
          l.comment ? (
            <div key={i} className="text-white/40">
              {l.comment}
            </div>
          ) : (
            <div key={i}>
              <span className="select-none text-accent">$ </span>
              {l.cmd}
            </div>
          ),
        )}
      </pre>
    </div>
  );
}
