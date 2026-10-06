import type { Metadata, Viewport } from "next";
import {
  IBM_Plex_Mono,
  IBM_Plex_Sans,
  IBM_Plex_Sans_Condensed,
  IBM_Plex_Sans_Devanagari,
} from "next/font/google";
import { getLocale, getTranslations } from "next-intl/server";

import "./globals.css";

// IBM Plex (SIL Open Font License): downloaded at build time and served as
// static files, so fonts cost nothing at runtime. Only the weights we use.
// Only the two faces every page needs above the fold are preloaded (speed
// budget: largest paint ≤ 2.5 s on a mid-range phone). The rest load on use.
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "600"],
});
const plexSansItalic = IBM_Plex_Sans({
  variable: "--font-plex-sans-italic",
  subsets: ["latin"],
  weight: ["500"],
  style: ["italic"],
  preload: false,
});
const plexCondensed = IBM_Plex_Sans_Condensed({
  variable: "--font-plex-condensed",
  subsets: ["latin"],
  weight: ["600"],
});
const plexMono = IBM_Plex_Mono({
  variable: "--font-plex-mono",
  subsets: ["latin"],
  weight: ["400"],
  preload: false,
});
const plexDevanagari = IBM_Plex_Sans_Devanagari({
  variable: "--font-plex-devanagari",
  subsets: ["devanagari"],
  weight: ["400", "500", "600"],
  // Only needed once Hindi ships; don't preload it for English pages.
  preload: false,
});

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("Metadata");
  return { title: t("title"), description: t("description") };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#e3eaec" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1720" },
  ],
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const locale = await getLocale();
  return (
    <html
      lang={locale}
      className={`${plexSans.variable} ${plexSansItalic.variable} ${plexCondensed.variable} ${plexMono.variable} ${plexDevanagari.variable} h-full antialiased`}
    >
      {/* Translations render on the server. Client components that need
          strings get a NextIntlClientProvider around just their subtree, so
          pages without them ship no i18n JavaScript. */}
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
