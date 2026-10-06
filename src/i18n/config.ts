/**
 * Locales. English ships first; Hindi is next (docs/design.md section 11).
 * Each locale will be a static route segment (`/hi/...`) so pages stay
 * pre-rendered: reading the language from cookies or headers would make every
 * page render on the server per request, which costs Worker CPU.
 */
export const locales = ["en"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "en";
