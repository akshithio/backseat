import {
  DM_Mono,
  Geist,
  Geist_Mono,
  IBM_Plex_Mono,
  IBM_Plex_Sans,
  Inter,
  Inter_Tight,
  Instrument_Sans,
  JetBrains_Mono,
  Silkscreen,
  Space_Grotesk,
  Space_Mono,
} from "next/font/google";

// Current pairing.
export const jetbrains = JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" });
export const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

// Candidates for the font picker on the local dev server. Not preloaded, so a
// browser only downloads the ones the picker actually switches to.
const spaceGrotesk = Space_Grotesk({ subsets: ["latin"], preload: false, variable: "--font-space-grotesk" });
const spaceMono = Space_Mono({ subsets: ["latin"], preload: false, weight: ["400", "700"], variable: "--font-space-mono" });
const plexSans = IBM_Plex_Sans({ subsets: ["latin"], preload: false, variable: "--font-plex-sans" });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], preload: false, weight: ["400", "500", "600", "700"], variable: "--font-plex-mono" });
const interTight = Inter_Tight({ subsets: ["latin"], preload: false, variable: "--font-inter-tight" });
const inter = Inter({ subsets: ["latin"], preload: false, variable: "--font-inter" });
const geistMono = Geist_Mono({ subsets: ["latin"], preload: false, variable: "--font-geist-mono" });
const instrument = Instrument_Sans({ subsets: ["latin"], preload: false, variable: "--font-instrument" });
const dmMono = DM_Mono({ subsets: ["latin"], preload: false, weight: ["400", "500"], variable: "--font-dm-mono" });
const silkscreen = Silkscreen({ subsets: ["latin"], preload: false, weight: ["400", "700"], variable: "--font-silkscreen" });

export const candidateVariables = [
  spaceGrotesk, spaceMono, plexSans, plexMono, interTight, inter, geistMono, instrument, dmMono, silkscreen,
].map((f) => f.variable).join(" ");
