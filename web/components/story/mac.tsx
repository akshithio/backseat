// SVG doodles of a Mac, drawn in a 160 x 100 stage.

import type { ReactNode } from "react";

const INK = "var(--color-ink)";

export function Wallpaper() {
  return (
    <g>
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#cfe6ec" />
          <stop offset="1" stopColor="#cfe6ff" />
        </linearGradient>
      </defs>
      <rect width="160" height="100" fill="url(#sky)" />
      <circle cx="132" cy="80" r="10" fill="#cfcfcf" opacity="0.8" />
      <path d="M0 88 C30 76 52 92 80 84 S130 74 160 86 V100 H0Z" fill="#9fc79a" opacity="0.75" />
      <path d="M0 94 C40 86 70 98 110 92 S150 90 160 94 V100 H0Z" fill="#7fb07a" opacity="0.8" />
    </g>
  );
}

export function MenuBar({ app, space = 1, spaces = 2 }: { app: string; space?: number; spaces?: number }) {
  return (
    <g>
      <rect width="160" height="5.6" fill="#ffffff" opacity="0.92" />
      <line x1="0" y1="5.6" x2="160" y2="5.6" stroke={INK} strokeWidth="0.25" opacity="0.4" />
      <circle cx="4.2" cy="2.8" r="1.3" fill={INK} />
      <text x="8" y="3.9" fontSize="2.5" fontWeight="700" fill={INK}>
        {app}
      </text>
      <text x={9 + app.length * 1.6} y="3.9" fontSize="2.3" fill={INK} opacity="0.55">
        File  Edit  View
      </text>
      {Array.from({ length: spaces }, (_, i) => (
        <rect
          key={i}
          x={136 + i * 4}
          y="1.6"
          width="3"
          height="2.4"
          rx="0.5"
          fill={i + 1 === space ? INK : "none"}
          stroke={INK}
          strokeWidth="0.3"
        />
      ))}
      <text x={134} y="3.9" fontSize="2.3" fill={INK} textAnchor="end" opacity="0.7">
        9:41
      </text>
    </g>
  );
}

export function Win({
  x,
  y,
  w,
  h,
  title,
  active = false,
  outline = 0,
  children,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  title: string;
  active?: boolean;
  /** 0..1 green outline strength */
  outline?: number;
  children?: ReactNode;
}) {
  return (
    <g transform={`translate(${x} ${y})`}>
      {active ? <rect x="1.2" y="1.4" width={w} height={h} rx="1.8" fill={INK} opacity="0.18" /> : null}
      <rect width={w} height={h} rx="1.8" fill="#ffffff" stroke={INK} strokeWidth="0.45" />
      <path
        d={`M0 1.8a1.8 1.8 0 0 1 1.8-1.8h${w - 3.6}a1.8 1.8 0 0 1 1.8 1.8V6H0Z`}
        fill={active ? "#efeeea" : "#f2f1ed"}
      />
      <line x1="0" y1="6" x2={w} y2="6" stroke={INK} strokeWidth="0.3" opacity="0.5" />
      {["#ff6159", "#ffbd2e", "#28c840"].map((c, i) => (
        <circle key={c} cx={3 + i * 3} cy="3" r="0.95" fill={active ? c : "#d4d3ce"} />
      ))}
      <text
        x={w / 2}
        y="4"
        fontSize="2.4"
        textAnchor="middle"
        fill={INK}
        opacity={active ? 1 : 0.45}
        fontWeight={active ? 700 : 400}
      >
        {title}
      </text>
      <g transform="translate(0 6)">{children}</g>
      {outline > 0 ? (
        <g opacity={outline}>
          <rect
            x="-1.1"
            y="-1.1"
            width={w + 2.2}
            height={h + 2.2}
            rx="2.6"
            fill="none"
            stroke="var(--color-go)"
            strokeWidth="2.2"
            opacity="0.22"
          />
          <rect
            x="-0.8"
            y="-0.8"
            width={w + 1.6}
            height={h + 1.6}
            rx="2.4"
            fill="none"
            stroke="var(--color-go)"
            strokeWidth="0.8"
          />
        </g>
      ) : null}
    </g>
  );
}

/** Wrap mono text into lines of at most n characters. */
export function wrap(text: string, n: number) {
  const out: string[] = [];
  for (const para of text.split("\n")) {
    let line = "";
    for (const word of para.split(" ")) {
      if (line && (line + " " + word).length > n) {
        out.push(line);
        line = word;
      } else line = line ? line + " " + word : word;
    }
    out.push(line);
  }
  return out;
}

/** Typed text with a blinking caret after the last character. */
export function Typing({
  x,
  y,
  text,
  cols,
  size = 2.7,
  lead = 4.2,
  caret = true,
  color = INK,
}: {
  x: number;
  y: number;
  text: string;
  cols: number;
  size?: number;
  lead?: number;
  caret?: boolean;
  color?: string;
}) {
  const lines = wrap(text, cols);
  const last = lines[lines.length - 1] ?? "";
  const cx = x + last.length * size * 0.6 + 0.3;
  const cy = y + (lines.length - 1) * lead;
  return (
    <g>
      {lines.map((l, i) => (
        <text key={i} x={x} y={y + i * lead} fontSize={size} fill={color} xmlSpace="preserve">
          {l}
        </text>
      ))}
      {caret ? <rect className="caret" x={cx} y={cy - size * 0.85} width="0.4" height={size * 1.05} fill={INK} /> : null}
    </g>
  );
}

export function FileIcon({ x, y, label, folder = false, hl = false }: { x: number; y: number; label: string; folder?: boolean; hl?: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      {hl ? <rect x="-2.5" y="-1" width="13" height="15" rx="1.4" fill="var(--color-claude)" opacity="0.18" /> : null}
      {folder ? (
        <path d="M0 2.5h3l1 1.2h4v6.3H0Z" fill="#7cb4e8" stroke={INK} strokeWidth="0.3" />
      ) : (
        <path d="M1 0h4.5l2 2v8.5H1Z M5.5 0v2h2" fill="#fff" stroke={INK} strokeWidth="0.3" />
      )}
      <text x="4" y="13" fontSize="1.7" textAnchor="middle" fill={INK}>
        {label}
      </text>
    </g>
  );
}

/** A little sticker label living in the stage. */
export function Chip({
  x,
  y,
  children,
  tone = "plain",
  o = 1,
  anchor = "start",
}: {
  x: number;
  y: number;
  children: string;
  tone?: "plain" | "bad" | "good" | "claude" | "sun";
  o?: number;
  anchor?: "start" | "end" | "middle";
}) {
  const fill = {
    plain: "#ffffff",
    bad: "var(--color-bad)",
    good: "var(--color-go)",
    claude: "var(--color-claude)",
    sun: "var(--color-sun)",
  }[tone];
  const text = tone === "plain" || tone === "sun" ? INK : "#ffffff";
  const w = children.length * 1.38 + 3;
  const left = anchor === "start" ? x : anchor === "end" ? x - w : x - w / 2;
  if (o <= 0.001) return null;
  return (
    <g opacity={o}>
      <rect x={left} y={y} width={w} height="4.2" rx="0.4" fill={fill} stroke={INK} strokeWidth="0.25" />
      <text x={left + 1.5} y={y + 2.95} fontSize="2.3" fill={text} fontWeight="700" xmlSpace="preserve">
        {children}
      </text>
    </g>
  );
}

/** The thing everybody wants: keyboard focus. */
export function FocusToken({ x, y, r = 0, o = 1 }: { x: number; y: number; r?: number; o?: number }) {
  return (
    <g transform={`translate(${x} ${y}) rotate(${r})`} opacity={o}>
      <rect width="15" height="5" rx="2.5" fill="var(--color-sun)" stroke={INK} strokeWidth="0.4" />
      <rect x="2" y="1.4" width="3" height="2.2" rx="0.4" fill="none" stroke={INK} strokeWidth="0.35" />
      <text x="6.2" y="3.4" fontSize="2.3" fontWeight="700" fill={INK}>
        focus
      </text>
    </g>
  );
}

/** A speaker with sound waves, optionally muted. */
export function Speaker({ x, y, muted = false, o = 1 }: { x: number; y: number; muted?: boolean; o?: number }) {
  return (
    <g transform={`translate(${x} ${y})`} opacity={o} stroke={INK} strokeWidth="0.5" fill="none" strokeLinecap="round">
      <path d="M0 2h2l3-2.5v8L2 5H0Z" fill="#ffffff" />
      {muted ? (
        <path d="M7 0.5l4.5 5M11.5 0.5L7 5.5" stroke="var(--color-bad)" strokeWidth="0.8" />
      ) : (
        <>
          <path d="M6.6 1a3.2 3.2 0 0 1 0 4.5" />
          <path d="M8.4 -0.6a5.6 5.6 0 0 1 0 7.7" />
        </>
      )}
    </g>
  );
}

export function Screen({ children }: { children: ReactNode }) {
  return (
    <g>
      <defs>
        <clipPath id="screen-clip">
          <rect width="160" height="100" />
        </clipPath>
      </defs>
      <g clipPath="url(#screen-clip)">{children}</g>
    </g>
  );
}
