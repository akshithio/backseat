"use client";

import { Mark } from "@/components/Mark";
import { Story } from "./engine";
import { Chapter, HeroStage } from "./parts";
import {
  LaneVisual,
  MannersVisual,
  OldVisual,
  PowersVisual,
  ShareVisual,
  heroChoreo,
  laneChoreo,
  mannersChoreo,
  oldChoreo,
  powersChoreo,
  shareChoreo,
} from "./scenes";

export function StorySection() {
  return (
    <Story>
      <HeroStage choreo={heroChoreo} className="relative mx-auto flex min-h-[92svh] max-w-[1120px] flex-col px-4 sm:px-6">
        <header className="flex items-center justify-between gap-4 py-5 text-[12px] tracking-[0.04em]">
          <a href="#top" className="flex items-center gap-2 font-bold text-ink">
            <Mark className="h-7 w-7 text-ink" wave />
            backseat
          </a>
          <nav className="flex items-center gap-4 text-muted sm:gap-6">
            <a href="#how" className="hidden transition-colors hover:text-ink sm:inline">
              how it works
            </a>
            <a href="#numbers" className="transition-colors hover:text-ink">
              numbers
            </a>
            <a href="#install" className="sticker bg-ink px-2.5 py-1 font-bold text-paper transition-opacity hover:opacity-80">
              install
            </a>
          </nav>
        </header>

        <div id="top" className="flex flex-1 flex-col justify-center pb-16 pt-6">
          <h1 aria-label="backseat" className="display wordmark mt-1 text-[clamp(4.2rem,17vw,12.5rem)] leading-[0.82] text-ink">
            {"back".split("").map((c, i) => (
              <span key={i} className="jiggle">
                {c}
              </span>
            ))}
            {"seat".split("").map((c, i) => (
              <span key={i} className="jiggle text-accent">
                {c}
              </span>
            ))}
          </h1>
          <p className="mt-7 max-w-[34rem] text-[17px] leading-[1.6] text-ink sm:text-[19px]">
            A Computer Use MCP that allows you and your agent to work simultaneously
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a href="#install" className="btn btn-ink">
              get it running
            </a>
            <a href="#act-1" className="btn">
              watch the story ↓
            </a>
          </div>
        </div>

      </HeroStage>

      <Chapter
        id="act-1"
        era="before"
        n="before · 01"
        title={<>One Mac. One&nbsp;cursor.</>}
        choreo={shareChoreo}
        Visual={ShareVisual}
        beats={[
          [0, "you're writing a list"],
          [0.35, "claude and codex need the same Mac"],
          [0.7, "…and there's only one focus"],
        ]}
      >
        <p>Whoever holds the pointer and the keyboard is driving.</p>
      </Chapter>

      <Chapter
        id="act-2"
        era="before"
        flip
        n="before · 02"
        tone="bad"
        title={<>Today: the agent takes&nbsp;over.</>}
        choreo={oldChoreo}
        Visual={OldVisual}
        beats={[
          [0, "you're writing, full screen"],
          [0.3, "the agent takes your pointer and pulls you away"],
          [0.68, "you wait until it's done"],
        ]}
      >
        <p>It moves your pointer and pulls apps in front of you. You wait.</p>
      </Chapter>

      <Chapter
        id="act-3"
        era="after"
        n="with backseat · 03"
        tone="good"
        title={<>backseat: you both work at&nbsp;once.</>}
        choreo={laneChoreo}
        Visual={LaneVisual}
        beats={[
          [0, "you keep writing"],
          [0.33, "claude works in its own window, outlined in green"],
          [0.75, "you never left Notes"],
        ]}
        note="(claude's cursor is drawn for the story. on your Mac, the green outline is all you'd see.)"
      >
        <p>The agent works in its own window, outlined in green. Your pointer and keyboard stay yours.</p>
      </Chapter>

      <Chapter
        id="act-4"
        era="after"
        flip
        n="with backseat · 04"
        title={<>It can use any&nbsp;app.</>}
        choreo={powersChoreo}
        Visual={PowersVisual}
        beats={[
          [0, "it reads the window"],
          [0.33, "fills fields, presses buttons, picks menu items"],
          [0.7, "and scripts apps that support it"],
        ]}
      >
        <p>Buttons, fields, menus, scripts. All in the background.</p>
      </Chapter>

      <Chapter
        id="act-5"
        era="after"
        n="with backseat · 05"
        tone="good"
        title={<>It never gets in your&nbsp;way.</>}
        choreo={mannersChoreo}
        Visual={MannersVisual}
        beats={[
          [0, "you, typing"],
          [0.3, "input an app would beep at is never sent"],
          [0.6, "an app jumps forward, and your focus comes straight back"],
        ]}
      >
        <p>No beeps, no stray menus. If an app jumps forward, you get your focus back in milliseconds.</p>
      </Chapter>
    </Story>
  );
}
