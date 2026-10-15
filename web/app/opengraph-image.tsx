import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "backseat: you and your agent on one Mac, at the same time";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const INK = "#1f1f1d";
const FINGERS: [number, number, number][] = [
  [11.6, 7.2, 17],
  [15.2, 5, 17],
  [18.8, 5.8, 17],
  [22.2, 8.6, 18],
];

// The site's waving open-hand mark, with its colors spelled out.
function Hand() {
  return (
    <svg width="120" height="120" viewBox="0 0 32 32">
      <g transform="rotate(-14 17 28)">
        <rect x="8.6" y="13.4" width="16.4" height="15" rx="6" fill={INK} />
        {FINGERS.map(([x, top, bottom]) => (
          <g key={x}>
            <path d={`M${x} ${bottom}V${top}`} stroke={INK} strokeWidth="4.4" strokeLinecap="round" />
            <path d={`M${x} ${bottom}V${top}`} stroke="#ffffff" strokeWidth="2.2" strokeLinecap="round" />
          </g>
        ))}
        <path d="M10.6 21.2L6.4 15.6" stroke={INK} strokeWidth="4.4" strokeLinecap="round" />
        <path d="M10.6 21.2L6.4 15.6" stroke="#ffffff" strokeWidth="2.2" strokeLinecap="round" />
        <rect x="9.7" y="15.6" width="14.2" height="11.7" rx="5" fill="#ffffff" />
        <path d="M13.2 20.6c1.4 1.2 3 1.6 4.6 1.2" stroke={INK} strokeWidth="0.9" strokeLinecap="round" fill="none" />
      </g>
      <path d="M25.8 4.4a5 5 0 0 1 3.4 4.2" stroke={INK} strokeWidth="1.5" strokeLinecap="round" fill="none" />
      <path d="M24.6 7.2a2.6 2.6 0 0 1 1.8 2.2" stroke={INK} strokeWidth="1.5" strokeLinecap="round" fill="none" />
    </svg>
  );
}

export default async function Image() {
  const sans = await readFile(join(process.cwd(), "assets/Arimo-Regular.ttf"));

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "88px 104px",
          background: "#faf9f7",
          color: INK,
          fontFamily: "Arimo",
        }}
      >
        <Hand />
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", fontSize: 96, letterSpacing: "-0.03em" }}>
            <span>back</span>
            <span style={{ color: "#0682FE" }}>seat</span>
          </div>
          <div style={{ marginTop: 20, maxWidth: 820, fontSize: 36, lineHeight: 1.45 }}>
            A Computer Use MCP that allows you and your agent to work simultaneously.
          </div>
          <div style={{ marginTop: 40, fontSize: 26, color: "#8c8a84" }}>backseat.akshith.io</div>
        </div>
      </div>
    ),
    { ...size, fonts: [{ name: "Arimo", data: sans, style: "normal", weight: 400 }] },
  );
}
