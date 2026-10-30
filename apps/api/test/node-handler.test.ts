import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import type { FastifyInstance } from "fastify";
import { afterAll, afterEach, beforeAll, expect, it, vi } from "vitest";
import { createNodeHandler, toApiPath, type NodeHandler } from "../src/node-handler.ts";
import { createTestApp, type TestApp } from "./support/app.ts";
import { closeOwnerPool } from "./support/db.ts";

let t: TestApp;
let server: Server | undefined;

beforeAll(async () => {
  t = await createTestApp();
});

afterEach(async () => {
  await new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve()));
  server = undefined;
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

/** Serves `handler` the way Vercel calls it, and returns the base URL. */
async function serve(handler: NodeHandler): Promise<string> {
  server = createServer((req, res) => void handler(req, res));
  await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

it.each([
  ["/api/me", "/me"],
  ["/api/terms/x/sections?a=1", "/terms/x/sections?a=1"],
  ["/api", "/"],
  ["/api/", "/"],
  ["/api?a=1", "/?a=1"],
  ["/apiary", "/apiary"],
  ["/me", "/me"],
])("maps %s to the API path %s", (url, path) => {
  expect(toApiPath(url)).toBe(path);
});

it("routes /api requests to the app without the prefix", async () => {
  const base = await serve(createNodeHandler(async () => t.app));
  const health = await fetch(`${base}/api/health`);
  expect([health.status, await health.json()]).toEqual([200, { status: "ok" }]);
  const me = await fetch(`${base}/api/me`);
  expect([me.status, await me.json()]).toEqual([
    401,
    { error: { code: "unauthorized", message: "Sign in to continue." } },
  ]);
});

it("builds the app once for many requests", async () => {
  const createApp = vi.fn(async () => t.app);
  const base = await serve(createNodeHandler(createApp));
  await fetch(`${base}/api/health`);
  await fetch(`${base}/api/health`);
  expect(createApp).toHaveBeenCalledTimes(1);
});

it("answers 500 when the app cannot start, then tries again on the next request", async () => {
  const failure = new Error("DATABASE_URL is missing");
  const createApp = vi
    .fn<() => Promise<FastifyInstance>>()
    .mockRejectedValueOnce(failure)
    .mockResolvedValue(t.app);
  const logError = vi.fn();
  const base = await serve(createNodeHandler(createApp, { logError }));

  const first = await fetch(`${base}/api/health`);
  expect([first.status, await first.json()]).toEqual([
    500,
    { error: { code: "internal", message: "Something went wrong. Please try again." } },
  ]);
  expect(logError).toHaveBeenCalledWith(failure);

  const second = await fetch(`${base}/api/health`);
  expect(second.status).toBe(200);
  expect(createApp).toHaveBeenCalledTimes(2);
});
