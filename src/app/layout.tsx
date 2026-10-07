import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans, IBM_Plex_Sans_Condensed } from "next/font/google";
import { getLocale, getTranslations } from "next-intl/server";

import "./globals.css";

// Self-hosted at build time (free). Only the faces every page needs are
// preloaded; more weights would push largest paint past the 2.5 s budget.
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "600"],
});
const plexCondensed = IBM_Plex_Sans_Condensed({
  variable: "--font-plex-condensed",
  subsets: ["latin"],
  weight: ["600"],
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
  return (
    <html
      lang={await getLocale()}
      className={`${plexSans.variable} ${plexCondensed.variable} h-full antialiased`}
    >
      {/* Strings render on the server; client components get a
          NextIntlClientProvider around just their subtree when they need it. */}
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
