import { loadConfig } from "./config.ts";
import { buildProductionApp } from "./production.ts";

const config = loadConfig(process.env);
const app = await buildProductionApp(config);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => void app.close());
}

await app.listen({ port: config.port, host: config.host });
