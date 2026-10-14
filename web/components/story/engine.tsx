"use client";

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { CURSORS, type Cast, type Choreo, type CursorId } from "./choreo";

/*
  One rAF loop drives the whole story.

  Segments register themselves in document order:
  - scene: a tall section with a sticky stage. Scroll progress through the
    section is the scene's `t`; its choreography places the cursors in stage
    coordinates (160 x 100), mapped onto the stage's on-screen rect.
  - path: a winding connector. The cursors ride it at the viewport's middle.

  Cursor positions are eased toward their targets with an exponential spring,
  so jumps between segments flow instead of snapping.
*/

type SceneSeg = {
  kind: "scene";
  section: HTMLElement;
  stage: HTMLElement;
  choreo: Choreo;
  setT?: (t: number) => void;
  /** "time": the hero; always active while it holds the viewport middle */
  mode: "sticky" | "time";
  lastT: number;
};

type PathSeg = {
  kind: "path";
  el: HTMLElement;
  at: (f: number, wide: boolean) => [number, number];
  onProgress?: (f: number) => void;
  fadeOut?: boolean;
};

type Seg = SceneSeg | PathSeg;

type Ctx = {
  register: (seg: Seg) => () => void;
  reduced: boolean;
};

const StoryCtx = createContext<Ctx | null>(null);

export function useStory() {
  const ctx = useContext(StoryCtx);
  if (!ctx) throw new Error("useStory outside <Story>");
  return ctx;
}

export function useReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const on = () => setReduced(mq.matches);
    on();
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return reduced;
}

const COLORS: Record<CursorId, string> = {
  you: "var(--color-you)",
  claude: "var(--color-claude)",
  codex: "var(--color-codex)",
};

type Live = { x: number; y: number; o: number; r: number; init: boolean };

export function Story({ children }: { children: ReactNode }) {
  const segs = useRef<Seg[]>([]);
  const reduced = useReducedMotion();
  const reducedRef = useRef(reduced);
  reducedRef.current = reduced;

  const cursorEls = useRef<Partial<Record<CursorId, HTMLDivElement | null>>>({});
  const live = useRef<Record<CursorId, Live>>({
    you: { x: 0, y: 0, o: 0, r: 0, init: false },
    claude: { x: 0, y: 0, o: 0, r: 0, init: false },
    codex: { x: 0, y: 0, o: 0, r: 0, init: false },
  });
  const said = useRef<Partial<Record<CursorId, string | null>>>({});

  const [ctx] = useState<Ctx>(() => ({
    reduced: false,
    register(seg) {
      segs.current.push(seg);
      segs.current.sort((a, b) => {
        const ea = a.kind === "scene" ? a.section : a.el;
        const eb = b.kind === "scene" ? b.section : b.el;
        return ea.compareDocumentPosition(eb) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
      });
      return () => {
        segs.current = segs.current.filter((s) => s !== seg);
      };
    },
  }));

  useEffect(() => {
    let raf = 0;
    let last = performance.now();

    const frame = (now: number) => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const time = now / 1000;
      const vh = window.innerHeight;
      const vw = window.innerWidth;
      const vc = vh * 0.5;
      const wide = vw >= 768;
      const reducedNow = reducedRef.current;

      const list = segs.current;
      if (!list.length) return;

      // Skip all work once the story is fully off screen.
      const firstEl = list[0].kind === "scene" ? list[0].section : list[0].el;
      const lastSeg = list[list.length - 1];
      const lastEl = lastSeg.kind === "scene" ? lastSeg.section : lastSeg.el;
      const top = firstEl.getBoundingClientRect().top;
      const bottom = lastEl.getBoundingClientRect().bottom;
      if (top > vh || bottom < 0) {
        for (const id of CURSORS) {
          const el = cursorEls.current[id];
          if (el) el.style.opacity = "0";
          live.current[id].init = false;
        }
        return;
      }

      let cast: Partial<Record<CursorId, { x: number; y: number; o: number; r: number; say: string | null; press: number; ghost: boolean }>> | null = null;

      for (const seg of list) {
        if (seg.kind === "scene") {
          const r = seg.section.getBoundingClientRect();
          let t: number;
          if (seg.mode === "time") {
            t = 0;
          } else {
            const span = Math.max(1, r.height - vh);
            t = Math.min(1, Math.max(0, -r.top / span));
            if (reducedNow) t = Math.round(t * 6) / 6;
          }
          if (seg.setT && Math.abs(t - seg.lastT) > 0.0008) {
            seg.lastT = t;
            seg.setT(t);
          }
          const active =
            seg.mode === "time" ? r.bottom > vc : r.top <= vc && r.bottom > vc;
          if (active && !cast) {
            const s = seg.stage.getBoundingClientRect();
            const c: Cast = seg.choreo(t, reducedNow ? 0 : time);
            cast = {};
            for (const id of CURSORS) {
              const p = c[id];
              cast[id] = {
                x: s.left + (p.x / 160) * s.width,
                y: s.top + (p.y / 100) * s.height,
                o: p.o ?? 1,
                r: p.r ?? 0,
                say: p.say ?? null,
                press: p.press ?? 0,
                ghost: !!p.ghost,
              };
            }
          }
        } else {
          const r = seg.el.getBoundingClientRect();
          const f = (vc - r.top) / r.height;
          seg.onProgress?.(Math.min(1, Math.max(0, f)));
          if (!cast && r.top <= vc && r.bottom > vc) {
            cast = {};
            CURSORS.forEach((id, i) => {
              const fi = Math.max(0, f - i * 0.07);
              const [nx, ny] = seg.at(fi, wide);
              cast![id] = {
                x: r.left + nx * r.width + (i - 1) * (wide ? 16 : 10),
                y: r.top + ny * r.height,
                o: seg.fadeOut ? Math.max(0, 1 - f * 1.6) : 1,
                r: Math.sin(time * 2 + i) * (reducedNow ? 0 : 6),
                say: null,
                press: 0,
                ghost: false,
              };
            });
          }
        }
      }

      const k = reducedNow ? 1 : 1 - Math.exp(-dt * 11);
      for (const id of CURSORS) {
        const el = cursorEls.current[id];
        if (!el) continue;
        const L = live.current[id];
        const target = cast?.[id];
        if (!target) {
          L.o += (0 - L.o) * (reducedNow ? 1 : 1 - Math.exp(-dt * 8));
          el.style.opacity = L.o.toFixed(3);
          continue;
        }
        // Keep the arrow and its name tag on screen.
        target.x = Math.min(vw - (wide ? 84 : 72), Math.max(6, target.x));
        if (!L.init) {
          L.x = target.x;
          L.y = target.y;
          L.r = target.r;
          L.init = true;
        }
        L.x += (target.x - L.x) * k;
        L.y += (target.y - L.y) * k;
        L.r += (target.r - L.r) * k;
        L.o += (target.o - L.o) * (reducedNow ? 1 : 1 - Math.exp(-dt * 8));
        const scale = (wide ? 1 : 0.82) * (1 - target.press * 0.18);
        el.style.transform = `translate3d(${L.x.toFixed(1)}px, ${L.y.toFixed(1)}px, 0)`;
        el.style.opacity = L.o.toFixed(3);
        const arrow = el.firstElementChild as HTMLElement | null;
        if (arrow) arrow.style.transform = `rotate(${L.r.toFixed(1)}deg) scale(${scale.toFixed(3)})`;
        el.dataset.ghost = target.ghost ? "1" : "0";
        el.dataset.flip = L.x > vw - 190 ? "1" : "0";
        el.style.setProperty("--press", target.press.toFixed(3));
        if (said.current[id] !== target.say) {
          said.current[id] = target.say;
          const bubble = el.querySelector<HTMLElement>("[data-bubble]");
          if (bubble) {
            if (target.say) bubble.textContent = target.say;
            bubble.dataset.show = target.say ? "1" : "0";
          }
        }
      }
    };

    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <StoryCtx.Provider value={{ ...ctx, reduced }}>
      {children}
      <div aria-hidden className="pointer-events-none fixed inset-0 z-40 overflow-hidden">
        {CURSORS.map((id) => (
          <div
            key={id}
            ref={(el) => {
              cursorEls.current[id] = el;
            }}
            className="cursor-actor absolute left-0 top-0 opacity-0 will-change-transform"
            style={{ ["--c" as string]: COLORS[id] }}
          >
            <div className="origin-top-left">
              <span className="cursor-ripple" />
              {/* Figma-style pointer: a compact arrowhead, no tail. */}
              <svg width="20" height="20" viewBox="0 0 20 20" className="cursor-arrow block">
                <path d="M2.5 2.2 L17.2 7.6 L9.6 9.6 L7.6 17.2 Z" strokeLinejoin="round" />
              </svg>
            </div>
            <span className="cursor-tag">{id}</span>
            <span data-bubble data-show="0" className="cursor-bubble" />
          </div>
        ))}
      </div>
    </StoryCtx.Provider>
  );
}
