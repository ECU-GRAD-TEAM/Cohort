import { createContext, useContext, type ReactNode } from "react";
import type { ApiClient } from "./api.ts";

const ApiContext = createContext<ApiClient | null>(null);

export function ApiProvider({ client, children }: { client: ApiClient; children: ReactNode }) {
  return <ApiContext.Provider value={client}>{children}</ApiContext.Provider>;
}

export function useApi(): ApiClient {
  const client = useContext(ApiContext);
  if (client === null) {
    throw new Error("useApi must be used inside an <ApiProvider>.");
  }
  return client;
}
