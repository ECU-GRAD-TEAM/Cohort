import { renderHook } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import { API } from "../../test/server.ts";
import { createApiClient } from "./api.ts";
import { ApiProvider, useApi } from "./ApiContext.tsx";

describe("useApi", () => {
  it("returns the client given to the provider", () => {
    const client = createApiClient({ baseUrl: API, getAccessToken: async () => null });
    const wrapper = ({ children }: { children: ReactNode }) => <ApiProvider client={client}>{children}</ApiProvider>;
    const { result } = renderHook(() => useApi(), { wrapper });
    expect(result.current).toBe(client);
  });

  it("throws a clear error outside the provider", () => {
    // React logs the render error to the console before rethrowing it.
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      expect(() => renderHook(() => useApi())).toThrow("useApi must be used inside an <ApiProvider>.");
    } finally {
      consoleError.mockRestore();
    }
  });
});
