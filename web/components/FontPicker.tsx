"use client";

import { useEffect, useState } from "react";

// Dev-only: switch the site's font pairing live to compare options.
const OPTIONS = [
  { id: "current", label: "Geist + JetBrains Mono" },
  { id: "space", label: "Space Grotesk + Space Mono" },
  { id: "plex", label: "IBM Plex Sans + Plex Mono" },
  { id: "inter", label: "Inter Tight + Geist Mono" },
  { id: "instrument", label: "Instrument Sans + DM Mono" },
  { id: "pixel", label: "Silkscreen + Plex Mono" },
  { id: "sans", label: "Inter Tight + Inter (no mono)" },
];

export function FontPicker() {
  const [font, setFont] = useState("current");

  useEffect(() => {
    try {
      const saved = localStorage.getItem("backseat-font");
      if (saved) setFont(saved);
    } catch {
      /* storage blocked; start from the current pairing */
    }
  }, []);

  useEffect(() => {
    if (font === "current") delete document.documentElement.dataset.font;
    else document.documentElement.dataset.font = font;
    try {
      localStorage.setItem("backseat-font", font);
    } catch {
      /* storage blocked; the choice just won't persist */
    }
  }, [font]);

  return (
    <div className="fixed bottom-4 right-4 z-[100] w-[250px] rounded-[8px] border border-ink bg-card p-2 text-[11px] shadow-lg">
      <p className="px-1.5 pb-1 text-muted">fonts (local only)</p>
      {OPTIONS.map((o) => (
        <button
          key={o.id}
          type="button"
          onClick={() => setFont(o.id)}
          className={`block w-full cursor-pointer rounded-[4px] px-1.5 py-1 text-left ${font === o.id ? "bg-ink text-paper" : "hover:bg-paper"}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
