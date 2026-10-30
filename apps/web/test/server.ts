import type { MeResponse } from "@cohort/contracts";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";

export const API = "http://api.test";

export const defaultMe: MeResponse = {
  id: "5b2d6f0e-8f3a-4c1e-9d7b-2a1c3e4f5a6b",
  email: "sara@a.test",
  userType: "student",
  displayName: "Sara Student",
  tenant: { id: "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d", name: "Smoke University A" },
  roles: ["student"],
};

// Every page the app can reach is covered, so tests that render the whole app run with strict
// unhandled-request checking. Tests override a route with `server.use(...)`.
const defaultHandlers = [
  http.get(`${API}/me`, () => HttpResponse.json(defaultMe)),
  http.get(`${API}/terms`, () => HttpResponse.json({ terms: [] })),
  http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [] })),
  http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [] })),
  http.get(`${API}/terms/:termId/sections`, () => HttpResponse.json({ sections: [] })),
];

export const server = setupServer(...defaultHandlers);
