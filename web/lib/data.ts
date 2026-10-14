// Every number on the site comes from this file. Only real measurements go here.

export const SITE = {
  name: "backseat",
  url: "https://backseat.akshith.io",
  // TODO(owner): confirm once the repo is public.
  github: "https://github.com/akshithio/backseat",
  author: { name: "akshith", url: "https://akshith.io" },
};

/** Focus hand-back, measured with backseat's FocusGuard. */
export const FOCUS = {
  minMs: 3,
  maxMs: 23,
  activations: 6,
};

export type BenchTask = {
  id: string;
  before: { calls: number; seconds: number };
  after: { calls: number; seconds: number };
};

/**
 * 5 tasks from mac-agent-bench, run on a real Mac.
 * calls = the agent's tool calls, seconds = agent wall time.
 * before -> after backseat's latest tool changes.
 */
export const BENCH: BenchTask[] = [
  { id: "files-sort", before: { calls: 8, seconds: 37.2 }, after: { calls: 5, seconds: 15.9 } },
  { id: "move-conflict", before: { calls: 5, seconds: 17.6 }, after: { calls: 5, seconds: 15.6 } },
  { id: "inventory-note", before: { calls: 9, seconds: 36.0 }, after: { calls: 5, seconds: 14.5 } },
  { id: "grocery-edit", before: { calls: 6, seconds: 28.6 }, after: { calls: 6, seconds: 32.0 } },
  { id: "dedup-clipboard", before: { calls: 7, seconds: 33.8 }, after: { calls: 5, seconds: 14.0 } },
];

export const BENCH_TOTALS = {
  before: { calls: 35, seconds: 153.2 },
  after: { calls: 26, seconds: 92.0 },
};

/**
 * backseat vs Codex computer use. NOT measured yet.
 * Drop recordings into /public and fill this in; the section renders them
 * instead of the placeholder. Leave `rows` empty until there are real numbers.
 */
export type HeadToHead = {
  backseatVideo?: string; // e.g. "/compare/backseat.mp4"
  codexVideo?: string; // e.g. "/compare/codex.mp4"
  task?: string;
  rows: { label: string; backseat: string; codex: string }[];
  note?: string;
};

export const HEAD_TO_HEAD: HeadToHead | null = null;

