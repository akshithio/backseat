// The five acts of the story, plus the hero. Each act has a choreography
// (where the three cursors are at progress t) and a Visual (the Mac at t).

import {
  lerp,
  pulse,
  ramp,
  step,
  track,
  typed,
  wobble,
  type Cast,
  type Choreo,
  type Pose,
} from "./choreo";
import {
  Chip,
  FileIcon,
  FocusToken,
  MenuBar,
  Screen,
  Speaker,
  Typing,
  Wallpaper,
  Win,
} from "./mac";

const ENTER: [number, number, number] = [0, 98, -6];
const bench = (t: number, time: number, say: [number, string | null][] = []): Pose => {
  const p = track([[0, 104, -6], [0.16, 145, 88]], t);
  const w = wobble(time, 3, 0.3);
  return { x: p.x + w.x, y: p.y + w.y, r: 24, say: step(say, t, null) };
};
const alive = (p: { x: number; y: number }, time: number, seed: number, amp = 0.5) => {
  const w = wobble(time, seed, amp);
  return { x: p.x + w.x, y: p.y + w.y };
};

/* ------------------------------------------------------------------ hero */

export const heroChoreo: Choreo = (_t, time) => ({
  you: { ...alive({ x: 14, y: 84 }, time, 1, 1.4) },
  claude: {
    x: 136 + Math.sin(time * 0.6) * 7,
    y: 26 + Math.cos(time * 0.8) * 5,
  },
  codex: { ...alive({ x: 150, y: 70 }, time, 2, 1.6), r: 8 },
});

/* -------------------------------------------------------- 1. one mac */

const GROCERIES = "groceries\n- eggs\n- oat milk\n- coffee (the good one)\n- basil, lots\n- birthday candles";

export const shareChoreo: Choreo = (t, time) => ({
  you: {
    ...alive(track([ENTER, [0.18, 34, 40], [0.4, 40, 44], [0.6, 36, 50], [0.8, 44, 48], [1, 38, 52]], t), time, 1),
    say: step([[0.93, "i'm typing."]], t, null),
  },
  claude: {
    ...alive(track([[0, 100, -6], [0.22, 104, 26], [0.4, 128, 32], [0.55, 112, 22], [0.72, 72, 12], [1, 68, 13]], t), time, 2),
    say: step([[0.7, "can i drive?"], [0.82, null]], t, null),
    press: pulse([0.4], t),
  },
  codex: {
    ...alive(track([[0, 104, -6], [0.26, 96, 74], [0.45, 126, 80], [0.6, 110, 70], [0.8, 74, 17], [1, 76, 19]], t), time, 3),
    say: step([[0.82, "no, me!"], [0.93, null]], t, null),
    press: pulse([0.45], t),
  },
});

export function ShareVisual({ t }: { t: number }) {
  const shake = t > 0.7 ? Math.sin(t * 220) * 6 * ramp(t, 0.7, 0.8) : 0;
  return (
    <Screen>
      <Wallpaper />
      <Win x={60} y={56} w={88} h={36} title="flights — Safari">
        <rect x="4" y="3" width="80" height="4" rx="2" fill="#f2f1ed" stroke="var(--color-ink)" strokeWidth="0.25" />
        {[11, 15, 19, 23].map((y, i) => (
          <rect key={y} x="4" y={y} width={[60, 72, 40, 54][i]} height="1.6" rx="0.8" fill="#e2e1dc" />
        ))}
      </Win>
      <Win x={84} y={10} w={70} h={40} title="Downloads">
        <FileIcon x={6} y={6} label="IMG_2041" />
        <FileIcon x={24} y={6} label="invoice.pdf" />
        <FileIcon x={42} y={6} label="todo.txt" />
        <FileIcon x={56} y={6} label="receipts" folder />
      </Win>
      <Win x={8} y={12} w={64} h={52} title="groceries — Notes" active>
        <Typing x={4} y={7} text={typed(GROCERIES, t, 0.16, 0.95)} cols={34} />
      </Win>
      <FocusToken x={50} y={7.4} r={shake} />
      <MenuBar app="Notes" />
    </Screen>
  );
}

/* ------------------------------------------------------- 2. the old way */

const ESSAY = "The trouble with sharing a computer is that only one of you can hold the";

export const oldChoreo: Choreo = (t, time) => {
  const shoved = ramp(t, 0.29, 0.36) - ramp(t, 0.62, 0.78);
  return {
    you: {
      ...alive(
        track(
          [ENTER, [0.12, 82, 46], [0.22, 86, 49], [0.29, 82, 46], [0.36, 22, 86], [0.6, 18, 82], [0.76, 40, 70], [0.9, 60, 58], [1, 62, 60]],
          t,
        ),
        time,
        1,
      ),
      r: -42 * shoved,
      say: step([[0.3, "hey!"], [0.44, null], [0.62, "(still typing…)"], [0.74, null], [0.86, "where's my essay?"]], t, null),
    },
    codex: {
      ...alive(
        track(
          [[0, 150, 8], [0.14, 132, 24], [0.22, 100, 40], [0.29, 82, 46], [0.42, 80, 52], [0.52, 64, 32], [0.6, 96, 36], [0.7, 112, 46], [0.8, 104, 62], [1, 108, 60]],
          t,
        ),
        time,
        3,
        0.3,
      ),
      say: step([[0.48, "Go to Folder…"], [0.6, null]], t, null),
      press: pulse([0.29, 0.52, 0.7], t),
    },
    claude: {
      ...alive(track([[0, 90, -6], [0.15, 12, 15], [1, 14, 17]], t), time, 2),
      say: step([], t, null),
    },
  };
};

export function OldVisual({ t }: { t: number }) {
  const shift = ramp(t, 0.36, 0.46);
  const onDesktop = shift > 0.5;
  const sheet = ramp(t, 0.48, 0.52);
  const beep = pulse([0.74], t, 0.07);
  const essay = typed(ESSAY, t, 0.02, 0.3);
  const goto = typed("~/Downloads/", t, 0.52, 0.6);
  const stray = typed("hold the", t, 0.62, 0.72);
  return (
    <Screen>
      <g transform={`translate(${shift * 160} 0)`}>
        {/* Space 1: the desktop, off to the left */}
        <g transform="translate(-160 0)">
          <Wallpaper />
          <Win x={18} y={12} w={124} h={70} title="Finder" active={onDesktop}>
            <FileIcon x={8} y={6} label="Applications" folder />
            <FileIcon x={28} y={6} label="Documents" folder />
            <FileIcon x={48} y={6} label="Downloads" folder />
            <FileIcon x={68} y={6} label="Desktop" folder />
            {sheet > 0 ? (
              <g transform={`translate(28 ${-14 + sheet * 14})`} opacity={sheet}>
                <rect x="0.8" y="0.8" width="68" height="24" rx="1.4" fill="var(--color-ink)" opacity="0.2" />
                <rect width="68" height="24" rx="1.4" fill="#ffffff" stroke="var(--color-ink)" strokeWidth="0.4" />
                <text x="4" y="6" fontSize="2.4" fontWeight="700" fill="var(--color-ink)">
                  Go to the folder:
                </text>
                <rect x="4" y="9" width="60" height="6" rx="1" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.35" />
                <text x="5.5" y="13" fontSize="2.6" fill="var(--color-ink)" xmlSpace="preserve">
                  {goto}
                  <tspan fill="var(--color-bad)" fontWeight="700">
                    {stray}
                  </tspan>
                </text>
                <rect x="48" y="17.5" width="16" height="4.4" rx="1" fill="var(--color-codex)" />
                <text x="56" y="20.7" fontSize="2.3" fill="#ffffff" textAnchor="middle">
                  Go
                </text>
              </g>
            ) : null}
          </Win>
          {beep > 0 ? (
            <g opacity={beep}>
              <Speaker x={124} y={40} />
              <text x="132" y="52" fontSize="4.2" fontWeight="700" fill="var(--color-bad)">
                (alert sound)
              </text>
            </g>
          ) : null}
        </g>
        {/* Space 2: your full-screen essay */}
        <rect width="160" height="100" fill="#ecebe7" />
        <rect x="0" y="5.6" width="160" height="6" fill="#efeeea" />
        <text x="80" y="9.6" fontSize="2.4" textAnchor="middle" fill="var(--color-ink)" fontWeight="700">
          essay — Pages (full screen)
        </text>
        <rect x="31.2" y="16.2" width="100" height="86" fill="var(--color-ink)" opacity="0.12" />
        <rect x="30" y="15" width="100" height="86" fill="#ffffff" stroke="var(--color-ink)" strokeWidth="0.3" />
        <text x="36" y="24" fontSize="3.6" fontWeight="700" fill="var(--color-ink)">
          On sharing
        </text>
        <Typing x={36} y={32} text={essay} cols={52} caret={!onDesktop} />
      </g>
      <MenuBar app={onDesktop ? "Finder" : "Pages"} space={onDesktop ? 1 : 2} />
      <Chip x={4} y={91} tone={onDesktop ? "bad" : "plain"}>
        {onDesktop ? "space 2 → 1" : "space 2"}
      </Chip>
      <Chip x={26} y={91} tone={onDesktop ? "bad" : "plain"}>
        {onDesktop ? "focus: Finder" : "focus: Pages"}
      </Chip>
      <Chip x={156} y={91} anchor="end" tone="bad" o={ramp(t, 0.86, 0.9)}>
        focus never came back
      </Chip>
    </Screen>
  );
}

/* --------------------------------------------------- 3. the backseat way */

const LETTER =
  "dear landlord,\nthe sink is making the noise again. it gurgles at 3am like it has opinions. video attached. also the hallway light flickers in what i'm fairly sure is morse code.";

export const laneChoreo: Choreo = (t, time) => {
  const dragging = t > 0.3 && t < 0.45 ? 0.5 : 0;
  return {
    you: {
      ...alive(track([ENTER, [0.12, 48, 46], [0.35, 52, 52], [0.6, 46, 56], [0.85, 54, 54], [1, 50, 58]], t), time, 1),
      say: step([[0.88, "wait, it's done?"]], t, null),
    },
    claude: {
      ...alive(
        track(
          [[0, 100, -6], [0.14, 108, 30], [0.3, 110, 33], [0.45, 142, 33], [0.52, 124, 48], [0.56, 95, 42], [0.72, 96, 43], [0.85, 128, 56], [1, 122, 52]],
          t,
        ),
        time,
        2,
        0.3,
      ),
      ghost: true,
      press: Math.max(dragging, pulse([0.3, 0.56], t)),
      say: step([[0.46, "moved invoice.pdf"], [0.55, null], [0.7, "renamed it"], [0.8, null]], t, null),
    },
    codex: bench(t, time, [[0.2, "(benched)"], [0.34, null]]),
  };
};

export function LaneVisual({ t }: { t: number }) {
  const outline = ramp(t, 0.04, 0.12);
  const drag = ramp(t, 0.3, 0.45);
  const gone = ramp(t, 0.45, 0.5);
  const ix = lerp(22, 54, drag);
  const iy = 6 - Math.sin(drag * Math.PI) * 5;
  const renaming = t >= 0.55;
  const name = renaming ? typed("sink.mov", t, 0.56, 0.66) || "IMG_2041" : "IMG_2041";
  return (
    <Screen>
      <Wallpaper />
      <Win x={84} y={16} w={70} h={46} title="Downloads" outline={outline}>
        <FileIcon x={6} y={6} label={name} hl={renaming && t < 0.72} />
        <FileIcon x={38} y={6} label="todo.txt" />
        <FileIcon x={54} y={6} label="receipts" folder hl={drag > 0.9 && gone < 1} />
        <g opacity={1 - gone}>
          <FileIcon x={ix} y={iy} label="invoice.pdf" hl={drag > 0 && drag < 1} />
        </g>
        <text x="35" y="36" fontSize="2" textAnchor="middle" fill="var(--color-ink)" opacity="0.45">
          {gone >= 1 ? "3 items" : "4 items"}
        </text>
      </Win>
      <Win x={6} y={10} w={72} h={62} title="letter — Notes" active>
        <Typing x={4} y={7} text={typed(LETTER, t, 0.02, 0.98)} cols={40} />
      </Win>
      <FocusToken x={52} y={6.8} />
      <MenuBar app="Notes" />
      <Chip x={4} y={91} tone="good" o={ramp(t, 0.1, 0.16)}>
        focus: yours
      </Chip>
      <Chip x={28} y={91} tone="good" o={ramp(t, 0.16, 0.22)}>
        space: same
      </Chip>
      <Chip x={50} y={91} tone="good" o={ramp(t, 0.22, 0.28)}>
        pointer: yours
      </Chip>
    </Screen>
  );
}

/* ------------------------------------------------------- 4. superpowers */

const LOG: [number, string][] = [
  [0.04, "get_ui_tree"],
  [0.22, "set_value"],
  [0.32, "set_value"],
  [0.42, "click"],
  [0.54, "select_menu_item"],
  [0.68, "run_script"],
  [0.84, "read_text"],
];

export const powersChoreo: Choreo = (t, time) => ({
  claude: {
    ...alive(
      track(
        [[0, 100, -6], [0.05, 60, 30], [0.16, 60, 36], [0.22, 42, 20], [0.32, 89, 20], [0.42, 94, 27], [0.54, 62, 46], [0.68, 66, 40], [0.84, 48, 47], [1, 50, 48]],
        t,
      ),
      time,
      2,
      0.3,
    ),
    ghost: true,
    press: pulse([0.22, 0.32, 0.42, 0.54], t),
    say: step([[0.85, "3 rows. got it."]], t, null),
  },
  you: {
    ...alive(track([ENTER, [0.12, 40, 84], [0.5, 50, 86], [1, 44, 88]], t), time, 1),
  },
  codex: bench(t, time, [[0.55, "zzz"], [0.7, null]]),
});

export function PowersVisual({ t }: { t: number }) {
  const ax = (i: number) => ramp(t, 0.04 + i * 0.025, 0.07 + i * 0.025) * (1 - ramp(t, 0.9, 0.98)) * 0.85;
  const added = t >= 0.43;
  const menu = ramp(t, 0.53, 0.56) * (1 - ramp(t, 0.65, 0.68));
  const script = ramp(t, 0.67, 0.7) * (1 - ramp(t, 0.8, 0.83));
  const box = (i: number, x: number, y: number, w: number, h: number, role: string) => (
    <g opacity={ax(i)}>
      <rect x={x - 0.8} y={y - 0.8} width={w + 1.6} height={h + 1.6} rx="0.8" fill="none" stroke="var(--color-claude)" strokeWidth="0.4" strokeDasharray="1 0.7" />
      <text x={x - 0.6} y={y - 1.4} fontSize="1.7" fill="var(--color-claude)" fontWeight="700">
        {role}
      </text>
    </g>
  );
  return (
    <Screen>
      <Wallpaper />
      <Win x={4} y={64} w={104} h={32} title="draft.txt — TextEdit" active>
        <Typing x={4} y={7} text={typed("notes from today: my expenses got filed while i wrote this. nobody touched my mouse.", t, 0.06, 0.96)} cols={60} />
      </Win>
      <Win x={4} y={8} w={104} h={52} title="Expenses" outline={1}>
        <text x="4" y="7" fontSize="2.2" fill="var(--color-ink)">Merchant</text>
        <rect x="16" y="3.6" width="42" height="5" rx="0.8" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.3" />
        <text x="17.2" y="7" fontSize="2.4" fill="var(--color-ink)">{typed("Blue Bottle", t, 0.22, 0.3)}</text>
        <text x="62" y="7" fontSize="2.2" fill="var(--color-ink)">Amount</text>
        <rect x="72" y="3.6" width="26" height="5" rx="0.8" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.3" />
        <text x="73.2" y="7" fontSize="2.4" fill="var(--color-ink)">{typed("4.50", t, 0.32, 0.37)}</text>
        <rect x="4" y="11.4" width="3" height="3" rx="0.4" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.3" />
        <text x="8.6" y="13.8" fontSize="2.2" fill="var(--color-ink)">reimbursable</text>
        <rect x="84" y="10.6" width="14" height="5" rx="1" fill={pulse([0.42], t, 0.03) > 0 ? "var(--color-claude)" : "#efeeea"} stroke="var(--color-ink)" strokeWidth="0.35" />
        <text x="91" y="14" fontSize="2.4" textAnchor="middle" fill="var(--color-ink)" fontWeight="700">Add</text>
        <g transform="translate(4 19)">
          <rect width="94" height="24" rx="0.8" fill="#fff" stroke="var(--color-ink)" strokeWidth="0.3" />
          <text x="2" y="3.6" fontSize="2" fill="var(--color-ink)" opacity="0.5">merchant</text>
          <text x="92" y="3.6" fontSize="2" fill="var(--color-ink)" opacity="0.5" textAnchor="end">amount</text>
          {[
            ["Philz", "5.25"],
            ["Tartine", "12.00"],
            ...(added ? [["Blue Bottle", "4.50"]] : []),
          ].map(([m, a], i) => (
            <g key={m} transform={`translate(0 ${8 + i * 5})`} className={m === "Blue Bottle" ? "pop-in" : undefined}>
              <text x="2" y="0" fontSize="2.4" fill="var(--color-ink)">{m}</text>
              <text x="92" y="0" fontSize="2.4" fill="var(--color-ink)" textAnchor="end">{a}</text>
            </g>
          ))}
        </g>
        {box(0, 16, 3.6, 42, 5, "AXTextField")}
        {box(1, 72, 3.6, 26, 5, "AXTextField")}
        {box(2, 4, 11.4, 22, 3, "AXCheckBox")}
        {box(3, 84, 10.6, 14, 5, "AXButton")}
        {box(4, 4, 19, 94, 24, "AXTable")}
      </Win>

      {/* tool log */}
      <g transform="translate(112 8)">
        <rect x="0.8" y="0.8" width="44" height="74" rx="1.8" fill="var(--color-ink)" />
        <rect width="44" height="74" rx="1.8" fill="#1c1c1b" stroke="var(--color-ink)" strokeWidth="0.4" />
        <text x="3" y="5.4" fontSize="2.5" fill="#ffffff" opacity="0.65">claude → backseat</text>
        {LOG.map(([at, name], i) => {
          const shown = t >= at;
          const current = shown && (i === LOG.length - 1 || t < LOG[i + 1][0]);
          if (!shown) return null;
          return (
            <g key={i} transform={`translate(3 ${13.5 + i * 8.6})`} className="pop-in">
              {current ? <rect x="-1.4" y="-3.4" width="41" height="5.4" rx="1" fill="var(--color-claude)" opacity="0.35" /> : null}
              <text x="0" y="0" fontSize="2.9" fill="#ffffff">{name}</text>
              <text x="38" y="0" fontSize="2.2" fill="var(--color-go-light)" textAnchor="end">{current ? "…" : "ok"}</text>
            </g>
          );
        })}
      </g>

      {/* menu picked through accessibility, never opened on your screen */}
      <g opacity={menu}>
        <Chip x={20} y={44}>{"File ▸ Export as CSV…"}</Chip>
      </g>
      <g opacity={script} transform="translate(14 36)">
        <rect x="0.8" y="0.8" width="74" height="13" rx="1.4" fill="var(--color-ink)" />
        <rect width="74" height="13" rx="1.4" fill="#ffffff" stroke="var(--color-ink)" strokeWidth="0.4" />
        <text x="3" y="5.2" fontSize="2.4" fill="var(--color-ink)">tell application &quot;Finder&quot;</text>
        <text x="3" y="9.8" fontSize="2.4" fill="var(--color-ink)">  make new folder at desktop</text>
      </g>
      <MenuBar app="TextEdit" />
    </Screen>
  );
}

/* --------------------------------------------------------- 5. manners */

const MINUTES =
  "minutes, oct 12\n- ship the site\n- review the numbers\n- next: run the Codex comparison";

export const mannersChoreo: Choreo = (t, time) => ({
  you: {
    ...alive(track([ENTER, [0.12, 52, 50], [0.62, 56, 56], [1, 52, 60]], t), time, 1),
    say: step([[0.86, "…did something happen?"]], t, null),
  },
  claude: {
    ...alive(
      track([[0, 100, -6], [0.08, 124, 38], [0.32, 128, 40], [0.38, 120, 44], [0.56, 122, 46], [0.6, 128, 32], [1, 132, 46]], t),
      time,
      2,
      0.3,
    ),
    ghost: true,
    press: pulse([0.1, 0.4], t),
    say: step([[0.1, "⌘⇧N"], [0.2, null], [0.4, "right-click?"], [0.5, null]], t, null),
  },
  codex: bench(t, time, [[0.92, "huh."]]),
});

export function MannersVisual({ t }: { t: number }) {
  const jumped = t >= 0.62 && t < 0.665;
  const a = ramp(t, 0.1, 0.13) * (1 - ramp(t, 0.32, 0.35));
  const b = ramp(t, 0.4, 0.43) * (1 - ramp(t, 0.56, 0.59));
  const c = ramp(t, 0.665, 0.69);
  return (
    <Screen>
      <Wallpaper />
      <g transform={jumped ? "translate(127 42) scale(1.05) translate(-127 -42)" : undefined}>
        <Win x={100} y={20} w={54} h={44} title={jumped ? "Go to Folder" : "Downloads"} outline={1} active={jumped}>
          <FileIcon x={5} y={6} label="sink.mov" />
          <FileIcon x={22} y={6} label="todo.txt" />
          <FileIcon x={39} y={6} label="receipts" folder />
        </Win>
      </g>
      <Win x={6} y={10} w={88} h={66} title="minutes — Notes" active={!jumped}>
        <Typing x={4} y={7} text={typed(MINUTES, t, 0.02, 0.98)} cols={50} caret={!jumped} />
      </Win>

      {/* beat A: shortcut that would beep */}
      <g opacity={a}>
        <Chip x={156} y={68} anchor="end">{"⌘⇧N: disabled in background"}</Chip>
        <Chip x={156} y={74} anchor="end" tone="sun">{"not sent. no beep."}</Chip>
        <Speaker x={102} y={84} muted />
      </g>

      {/* beat B: right-click that would pop a menu */}
      <g opacity={b}>
        <rect x="124" y="44" width="24" height="16" rx="1" fill="#ffffff" opacity="0.6" stroke="var(--color-ink)" strokeWidth="0.35" strokeDasharray="1 0.8" />
        {[48, 52, 56].map((y) => (
          <rect key={y} x="126" y={y} width="16" height="1.4" rx="0.7" fill="#e2e1dc" />
        ))}
        <path d="M124 44 L148 60 M148 44 L124 60" stroke="var(--color-bad)" strokeWidth="0.9" strokeLinecap="round" />
        <Chip x={156} y={68} anchor="end" tone="sun">{"context menu: refused"}</Chip>
      </g>

      {/* beat C: Finder activates itself, focus comes straight back */}
      <Chip x={156} y={68} anchor="end" tone="bad" o={jumped ? 1 : 0}>
        Finder jumped forward
      </Chip>
      <g opacity={c}>
        <Chip x={156} y={68} anchor="end" tone="good">{"focus back in 3–23 ms"}</Chip>
        <Chip x={156} y={74} anchor="end">{"measured over 6 activations"}</Chip>
        <Chip x={156} y={80} anchor="end" o={ramp(t, 0.72, 0.76)}>{"space: unchanged"}</Chip>
      </g>

      <FocusToken x={jumped ? 116 : 60} y={jumped ? 14 : 6.8} />
      <MenuBar app={jumped ? "Finder" : "Notes"} />
    </Screen>
  );
}

export type { Cast };
