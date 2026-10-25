import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach } from "vitest";
import { server } from "./server.ts";

server.listen({ onUnhandledFrame: "error" });
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
