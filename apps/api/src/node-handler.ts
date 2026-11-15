import type { IncomingMessage, ServerResponse } from "node:http";
import type { ApiErrorBody } from "@cohort/contracts";
import type { FastifyInstance } from "fastify";
import { INTERNAL_MESSAGE } from "./errors.ts";

export type NodeHandler = (req: IncomingMessage, res: ServerResponse) => Promise<void>;

/**
 * The path the API serves for a URL the platform received under `/api`: `/api/me?x=1` is
 * `/me?x=1` and `/api` is `/`. Other URLs are unchanged.
 */
export function toApiPath(url: string): string {
  if (!/^\/api(?=\/|\?|$)/.test(url)) return url;
  const rest = url.slice("/api".length);
  return rest.startsWith("/") ? rest : `/${rest}`;
}

/**
 * A Node.js request handler for a serverless function that serves the API under `/api`. The app
 * is built on the first request and reused while the function instance lives. If building it
 * fails, the request gets the API's 500 body and the next request tries again.
 */
export function createNodeHandler(
  createApp: () => Promise<FastifyInstance>,
  options: { logError?: (error: unknown) => void } = {},
): NodeHandler {
  const logError = options.logError ?? console.error;
  let ready: Promise<FastifyInstance> | undefined;

  return async (req, res) => {
    ready ??= createApp().then(async (app) => {
      await app.ready();
      return app;
    });

    let app: FastifyInstance;
    try {
      app = await ready;
    } catch (error) {
      ready = undefined;
      logError(error);
      const body: ApiErrorBody = { error: { code: "internal", message: INTERNAL_MESSAGE } };
      res.writeHead(500, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify(body));
      return;
    }

    req.url = toApiPath(req.url ?? "/");
    app.routing(req, res);
  };
}
