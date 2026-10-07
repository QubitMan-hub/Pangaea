import type {} from "next-intl";
import { getRequestConfig } from "next-intl/server";

import type messages from "../../messages/en.json";

// Fixed per build: reading the locale from cookies or headers would render
// every page per request (Worker CPU). Hindi will be a static /hi route.
const locale = "en";

export default getRequestConfig(async () => ({
  locale,
  messages: (await import(`../../messages/${locale}.json`)).default,
}));

// Type-checks every translation key against the English catalog.
declare module "next-intl" {
  interface AppConfig {
    Messages: typeof messages;
  }
}
