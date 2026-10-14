// Tiny keyframe toolkit. Scenes live in a 160 x 100 "stage" coordinate space.

export type CursorId = "you" | "claude" | "codex";
export const CURSORS: CursorId[] = ["you", "claude", "codex"];

export type Pose = {
  x: number;
  y: number;
  /** opacity 0..1 */
  o?: number;
  /** rotation in degrees */
  r?: number;
  /** speech bubble */
  say?: string | null;
  /** 0..1 click pulse */
  press?: number;
  /** drawn dashed: a virtual cursor that isn't on your real screen */
  ghost?: boolean;
};

export type Cast = Record<CursorId, Pose>;
export type Choreo = (t: number, time: number) => Cast;

export const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const smooth = (v: number) => v * v * (3 - 2 * v);
export const lerp = (a: number, b: number, k: number) => a + (b - a) * k;

/** 0 before a, 1 after b, eased in between. */
export const ramp = (t: number, a: number, b: number) => smooth(clamp((t - a) / (b - a)));

export type Key = [t: number, x: number, y: number];

/** Eased position along keyframes. */
export function track(keys: Key[], t: number): { x: number; y: number } {
  if (t <= keys[0][0]) return { x: keys[0][1], y: keys[0][2] };
  for (let i = 1; i < keys.length; i++) {
    const [t1, x1, y1] = keys[i];
    if (t <= t1) {
      const [t0, x0, y0] = keys[i - 1];
      const k = smooth((t - t0) / (t1 - t0 || 1));
      return { x: lerp(x0, x1, k), y: lerp(y0, y1, k) };
    }
  }
  const last = keys[keys.length - 1];
  return { x: last[1], y: last[2] };
}

/** Value of the last key at or before t. */
export function step<T>(keys: [number, T][], t: number, init: T): T {
  let v = init;
  for (const [k, val] of keys) if (t >= k) v = val;
  return v;
}

/** 1 exactly at one of `times`, falling to 0 within `w`. */
export function pulse(times: number[], t: number, w = 0.018) {
  let m = 0;
  for (const c of times) m = Math.max(m, 1 - Math.abs(t - c) / w);
  return clamp(m);
}

/** Characters of `text` typed between a and b. */
export function typed(text: string, t: number, a: number, b: number) {
  return text.slice(0, Math.round(clamp((t - a) / (b - a)) * text.length));
}

/** Small idle wobble so cursors look alive. */
export function wobble(time: number, seed: number, amp = 0.6) {
  return {
    x: Math.sin(time * 1.3 + seed * 2.1) * amp,
    y: Math.cos(time * 1.7 + seed * 1.3) * amp * 0.7,
  };
}
