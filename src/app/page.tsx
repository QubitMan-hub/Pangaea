import { getTranslations } from "next-intl/server";

export default async function Home() {
  const t = await getTranslations("Home");
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-6 px-4 py-24 text-center">
      <p className="font-condensed text-ink-3 text-xs font-semibold tracking-[0.22em] uppercase">
        {t("eyebrow")}
      </p>
      <h1 className="font-condensed text-5xl font-semibold tracking-tight text-balance">
        {t("title")}
      </h1>
      <p className="text-ink-2 max-w-xl text-lg leading-8">{t("promise")}</p>
      <p className="text-ink-3 text-sm">{t("status")}</p>
    </main>
  );
}
