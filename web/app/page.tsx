import { BenchRace } from "@/components/BenchRace";
import { FocusReplay } from "@/components/FocusReplay";
import { HeadToHead } from "@/components/HeadToHead";
import { Install } from "@/components/Install";
import { Mark } from "@/components/Mark";
import { StorySection } from "@/components/story/StorySection";
import { SITE } from "@/lib/data";

const HOW = [
  {
    title: "Accessibility first",
    body: "Reading UI trees, pressing buttons, setting values, typing at the caret, choosing menu items and scrolling all go through the Accessibility API. Nothing gets activated.",
    tag: "AXUIElement",
  },
  {
    title: "Clicks addressed to one window",
    body: "For canvases, drags and right-clicks, backseat builds mouse events stamped with a window number and posts them straight to that app's process. WindowServer never routes them, so there's no click-to-activate, even on covered windows.",
    tag: "CGEventPostToPid",
  },
  {
    title: "Keys to one process",
    body: "Shortcuts and typed keys reach a background app without touching your keyboard focus. ⌘ shortcuts are chosen from the menu bar, or refused when the item is disabled.",
    tag: "per-process keys",
  },
  {
    title: "Apple Events for the rest",
    body: "Save, Bold, New Folder: commands that act on the focused window are disabled in an app that isn't active. run_script sends Apple Events instead, which reach scriptable apps without bringing them forward.",
    tag: "run_script",
  },
  {
    title: "A safety net",
    body: "Some apps activate themselves anyway (Finder's Go to Folder, Safari's New Window). backseat hands focus straight back to your window and its Space, and keeps checking for a second in case the activation lands late.",
    tag: "FocusGuard",
  },
  {
    title: "Eyes on one window",
    body: "Screenshots capture a single window, even one on another Space or off screen. The green outline is drawn only where that window is visible to you, and is left out of the agent's screenshots.",
    tag: "ScreenCaptureKit",
  },
];

function SectionHead({ id, title, children }: { id: string; title: React.ReactNode; children?: React.ReactNode }) {
  return (
    <div id={id} className="scroll-mt-8">
      <h2 className="display text-[clamp(2.2rem,7vw,4.4rem)] leading-[0.95]">{title}</h2>
      {children ? <div className="mt-4 max-w-[38rem] text-[13.5px] leading-[1.75] text-ink/85">{children}</div> : null}
    </div>
  );
}

export default function Home() {
  return (
    <main>
      <StorySection />

      <section className="mx-auto max-w-[1120px] space-y-10 px-4 pb-24 sm:px-6">
        <SectionHead id="numbers" title="What we measured.">
          <p>Measured on a real Mac.</p>
        </SectionHead>
        <FocusReplay />
        <BenchRace />
        <HeadToHead />
      </section>

      <section className="mx-auto max-w-[1120px] px-4 pb-24 sm:px-6">
        <SectionHead id="how" title="How it works.">
          <p>
            One rule: nothing backseat does activates the app it&apos;s driving. Activation is what takes your keyboard
            focus, and what drags you across Spaces.
          </p>
        </SectionHead>
        <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {HOW.map((h, i) => (
            <article key={h.title} className="card p-5">
              <div className="flex items-center justify-between gap-3">
                <span className="display text-[34px] leading-none text-accent">{String(i + 1).padStart(2, "0")}</span>
                <code className="rounded-md border border-rule bg-paper px-2 py-0.5 text-[10.5px] text-muted">{h.tag}</code>
              </div>
              <h3 className="mt-4 text-[14px] font-bold">{h.title}</h3>
              <p className="mt-2 text-[12.5px] leading-[1.7] text-ink/80">{h.body}</p>
            </article>
          ))}
        </div>
        <p className="mt-8 max-w-[44rem] border-l-4 border-sun pl-4 text-[12.5px] leading-[1.75] text-ink/80">
          <b>The honest limitation.</b> An app that isn&apos;t scriptable and has no on-window control for a focus-only
          command can&apos;t run that command in the background. Doing it anyway means briefly taking focus, or running
          the app in a separate macOS session.
        </p>
      </section>

      <section className="mx-auto max-w-[1120px] px-4 pb-24 sm:px-6">
        <SectionHead id="install" title="Install it.">
          <p>
            One command builds backseat and adds it to Claude Code.
          </p>
        </SectionHead>
        <div className="mt-8 grid gap-8 md:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] md:items-start">
          <Install />
          <div className="space-y-4 text-[12.5px] leading-[1.75] text-ink/85">
            <p className="text-[14px] leading-[1.7] text-muted">
              then ask for something and keep working: &ldquo;tidy my Downloads while I finish this email.&rdquo;
            </p>
          </div>
        </div>
      </section>

      <footer className="border-t-2 border-ink bg-ink text-paper">
        <div className="mx-auto flex max-w-[1120px] flex-col gap-8 px-4 py-12 sm:px-6 md:flex-row md:items-end md:justify-between">
          <div>
            <div className="flex items-center gap-3">
              <Mark className="h-10 w-10 text-paper" />
              <span className="display text-[44px] leading-none">backseat</span>
            </div>
          </div>
          <nav className="flex flex-wrap items-baseline gap-x-5 gap-y-2 text-[11px] tracking-[0.08em] text-paper/60">
            <a href={SITE.github} target="_blank" rel="noreferrer" className="transition-colors hover:text-paper">
              github
            </a>
            <span className="text-paper/25">/</span>
            <a href="#install" className="transition-colors hover:text-paper">
              install
            </a>
            <span className="text-paper/25">/</span>
            <a href={SITE.author.url} target="_blank" rel="noreferrer" className="transition-colors hover:text-paper">
              made by {SITE.author.name}
            </a>
          </nav>
        </div>
      </footer>
    </main>
  );
}
