import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterAll, afterEach } from "vitest";
import { server } from "./server.ts";

server.listen({ onUnhandledFrame: "error" });
// Vitest globals are off, so Testing Library does not unmount rendered trees on its own.
afterEach(() => cleanup());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
