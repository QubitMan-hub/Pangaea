import { serverEnv } from "@/lib/env/server";
import { CRON_SECRET_HEADER, isJobName, secretsMatch } from "@/lib/jobs/schedule";

/**
 * Entry point for background jobs, called only by the Worker's own cron
 * handler (worker.ts). Each job will process one small batch and return.
 * Jobs are added in the phases that need them; until then this route only
 * authenticates and acknowledges.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/jobs/[job]">) {
  const { job } = await ctx.params;
  if (!secretsMatch(request.headers.get(CRON_SECRET_HEADER), serverEnv().CRON_SECRET)) {
    return new Response(null, { status: 404 });
  }
  if (!isJobName(job)) {
    return new Response(null, { status: 404 });
  }
  return Response.json({ job, status: "not-implemented" }, { status: 202 });
}
