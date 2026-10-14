import type { Metadata, Viewport } from "next";
import { Geist, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const jetbrains = JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" });
const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

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
  twitter: { card: "summary" },
};

export const viewport: Viewport = {
  themeColor: "#faf9f7",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${jetbrains.variable} ${geist.variable}`}>
      <body className="bg-paper font-mono text-ink antialiased">
        {children}
      </body>
    </html>
  );
}
