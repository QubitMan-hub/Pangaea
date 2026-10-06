import { initOpenNextCloudflareForDev } from "@opennextjs/cloudflare";
import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  // Every image is resized and encoded in the browser before upload, so
  // server-side optimization (metered Cloudflare Images) is never needed.
  images: { unoptimized: true },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          // Pangaea pages are never meant to be framed by other sites. A full
          // Content-Security-Policy comes with the editor in Phase 1, once we
          // know what tldraw needs.
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },
};

export default createNextIntlPlugin()(nextConfig);

// Lets `next dev` use Cloudflare bindings locally.
initOpenNextCloudflareForDev();
