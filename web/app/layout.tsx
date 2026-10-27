import type { Metadata, Viewport } from "next";
import { FontPicker } from "@/components/FontPicker";
import { candidateVariables, geist, jetbrains } from "./fonts";
import "./globals.css";

// The font picker is for choosing fonts locally; it never ships.
const dev = process.env.NODE_ENV === "development";

const description =
  "Computer use for macOS that doesn't take over your screen. Your agent drives apps in the background while your pointer, keyboard focus and Space stay yours.";

export const metadata: Metadata = {
  title: "backseat",
  description,
  metadataBase: new URL("https://backseat.akshith.io"),
  openGraph: {
    title: "backseat",
    description,
    url: "https://backseat.akshith.io",
    siteName: "backseat",
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = {
  themeColor: "#faf9f7",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${jetbrains.variable} ${geist.variable}${dev ? ` ${candidateVariables}` : ""}`}>
      <body className="bg-paper font-mono text-ink antialiased">
        {children}
        {dev ? <FontPicker /> : null}
      </body>
    </html>
  );
}
