import {
  Bricolage_Grotesque,
  Geist,
  Hanken_Grotesk,
  IBM_Plex_Sans,
  Inter,
  Inter_Tight,
  Instrument_Sans,
  JetBrains_Mono,
  Schibsted_Grotesk,
  Space_Grotesk,
} from "next/font/google";

// Current fonts: Geist for everything, JetBrains Mono only for code.
export const jetbrains = JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" });
export const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

// Candidates for the font picker on the local dev server. Not preloaded, so a
// browser only downloads the ones the picker actually switches to.
const inter = Inter({ subsets: ["latin"], preload: false, variable: "--font-inter" });
const interTight = Inter_Tight({ subsets: ["latin"], preload: false, variable: "--font-inter-tight" });
const instrument = Instrument_Sans({ subsets: ["latin"], preload: false, variable: "--font-instrument" });
const spaceGrotesk = Space_Grotesk({ subsets: ["latin"], preload: false, variable: "--font-space-grotesk" });
const hanken = Hanken_Grotesk({ subsets: ["latin"], preload: false, variable: "--font-hanken" });
const schibsted = Schibsted_Grotesk({ subsets: ["latin"], preload: false, variable: "--font-schibsted" });
const bricolage = Bricolage_Grotesque({ subsets: ["latin"], preload: false, variable: "--font-bricolage" });
const plexSans = IBM_Plex_Sans({ subsets: ["latin"], preload: false, variable: "--font-plex-sans" });

export const candidateVariables = [inter, interTight, instrument, spaceGrotesk, hanken, schibsted, bricolage, plexSans]
  .map((f) => f.variable)
  .join(" ");
