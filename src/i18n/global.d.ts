import type messages from "../../messages/en.json";

// Type-checks every translation key against the English catalog.
declare module "next-intl" {
  interface AppConfig {
    Messages: typeof messages;
  }
}
