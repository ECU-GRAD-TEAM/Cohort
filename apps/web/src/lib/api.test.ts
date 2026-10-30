import type { MeResponse } from "@cohort/contracts";
import { http, HttpResponse } from "msw";
import { describe, expect, it, vi } from "vitest";
import { API, server } from "../../test/server.ts";
import { ApiError, createApiClient } from "./api.ts";

const sectionId = "3f6c2a1e-8b4d-4c2a-9e1f-2b3c4d5e6f70";

const me: MeResponse = {
  id: "7b1d9c52-4e0a-4f3b-8a6d-1c2e3f405162",
  email: "ayla.hassan@cohort.test",
  userType: "student",
  displayName: "Ayla Hassan",
  tenant: { id: "a4c8e0f2-1b3d-4a5c-9e7f-0123456789ab", name: "Cohort University" },
  roles: ["student"],
};

const client = (onUnauthorized = vi.fn()) =>
  createApiClient({ baseUrl: API, getAccessToken: async () => "test-token", onUnauthorized });

describe("createApiClient", () => {
  it("sends the access token and parses the response", async () => {
    server.use(
      http.get(`${API}/me`, ({ request }) =>
        request.headers.get("authorization") === "Bearer test-token"
          ? HttpResponse.json(me)
          : new HttpResponse(null, { status: 401 }),
      ),
    );
    await expect(client().getMe()).resolves.toEqual(me);
  });

  it("surfaces the API's error code and message", async () => {
    server.use(
      http.post(`${API}/enrollments`, () =>
        HttpResponse.json(
          { error: { code: "rule_violation", message: "Prerequisites for CS201 are not met" } },
          { status: 422 },
        ),
      ),
    );
    await expect(client().enroll(sectionId)).rejects.toMatchObject({
      status: 422,
      code: "rule_violation",
      message: "Prerequisites for CS201 are not met",
    });
  });

  it("reports unreadable failures generically", async () => {
    server.use(http.get(`${API}/terms`, () => new HttpResponse("<html>Bad gateway</html>", { status: 502 })));
    await expect(client().getTerms()).rejects.toMatchObject({
      status: 502,
      code: "internal",
      message: "Something went wrong. Please try again.",
    });
  });

  it("signals an expired session", async () => {
    const onUnauthorized = vi.fn();
    server.use(
      http.get(`${API}/me/grades`, () =>
        HttpResponse.json({ error: { code: "unauthorized", message: "Sign in to continue." } }, { status: 401 }),
      ),
    );
    await expect(client(onUnauthorized).getMyGrades()).rejects.toMatchObject({ code: "unauthorized" });
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
  });

  it("refuses a response that breaks the contract", async () => {
    server.use(http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [{ id: 1 }] })));
    await expect(client().getMyEnrollments()).rejects.toMatchObject({
      code: "internal",
      message: "Unexpected response from the server.",
    });
  });

  it("drops with DELETE on the section's path", async () => {
    server.use(
      http.delete(`${API}/enrollments/${sectionId}`, () =>
        HttpResponse.json({ enrollment: { id: sectionId, sectionId, status: "dropped", waitlistPosition: null } }),
      ),
    );
    await expect(client().drop(sectionId)).resolves.toMatchObject({ enrollment: { status: "dropped" } });
  });

  it("enrolls with a JSON body", async () => {
    let received: { contentType: string | null; body: unknown } | undefined;
    server.use(
      http.post(`${API}/enrollments`, async ({ request }) => {
        received = { contentType: request.headers.get("content-type"), body: await request.json() };
        return HttpResponse.json(
          { enrollment: { id: sectionId, sectionId, status: "waitlisted", waitlistPosition: 3 } },
          { status: 201 },
        );
      }),
    );
    await expect(client().enroll(sectionId)).resolves.toMatchObject({
      enrollment: { status: "waitlisted", waitlistPosition: 3 },
    });
    expect(received).toEqual({ contentType: "application/json", body: { sectionId } });
  });

  it("encodes path parameters", async () => {
    let pathname: string | undefined;
    server.use(
      http.get(`${API}/terms/:termId/sections`, ({ request }) => {
        pathname = new URL(request.url).pathname;
        return HttpResponse.json({ sections: [] });
      }),
    );
    await expect(client().getSections("a/b c")).resolves.toEqual({ sections: [] });
    expect(pathname).toBe("/terms/a%2Fb%20c/sections");
  });

  it("signals an expired session even when the 401 body is unreadable", async () => {
    const onUnauthorized = vi.fn();
    server.use(http.get(`${API}/me`, () => new HttpResponse(null, { status: 401 })));
    await expect(client(onUnauthorized).getMe()).rejects.toMatchObject({ status: 401, code: "internal" });
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
  });

  it("turns a network failure into a generic error", async () => {
    const onUnauthorized = vi.fn();
    server.use(http.get(`${API}/terms`, () => HttpResponse.error()));
    const failure = client(onUnauthorized).getTerms();
    await expect(failure).rejects.toBeInstanceOf(ApiError);
    await expect(failure).rejects.toMatchObject({
      status: 0,
      code: "internal",
      message: "Something went wrong. Please try again.",
    });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });
});
