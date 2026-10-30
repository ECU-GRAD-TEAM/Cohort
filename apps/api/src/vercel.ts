// The API's entry point on Vercel: one Node.js function serving every request under /api.
// scripts/vercel/build.mjs bundles this file into the deployment.
import { loadConfig } from "./config.ts";
import { createNodeHandler } from "./node-handler.ts";
import { buildProductionApp } from "./production.ts";

export default createNodeHandler(async () => buildProductionApp(loadConfig(process.env)));
