import {
  EnrollmentsResponse,
  GradesResponse,
  MeResponse,
  ScheduleResponse,
  SectionsResponse,
  TeachingResponse,
  TermsResponse,
} from '@cohort/contracts';

const BASE = (import.meta.env.VITE_API_URL || '/api').replace(/\/$/, '');
const GENERIC = 'Something went wrong. Please try again.';

/** A failed API call, with the API's own code and message when it sent them. */
export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/**
 * The Cohort API, called as the signed-in user. `getToken` returns the current access token;
 * `onUnauthorized` runs on any 401, which means the session is no longer valid. Every answer is
 * checked against the shared contract, so the pages never see a shape they don't expect.
 */
export function createApi(getToken, onUnauthorized) {
  async function request(method, path, schema, body) {
    const token = await getToken();
    let response;
    try {
      response = await fetch(BASE + path, {
        method,
        headers: {
          authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError(0, 'network', 'Cohort could not be reached. Check your connection and try again.');
    }
    let json = null;
    try {
      json = await response.json();
    } catch {
      // A body that isn't JSON is handled as a generic failure below.
    }
    if (!response.ok) {
      if (response.status === 401) onUnauthorized?.();
      throw new ApiError(response.status, json?.error?.code ?? 'internal', json?.error?.message ?? GENERIC);
    }
    if (!schema) return json;
    const parsed = schema.safeParse(json);
    if (!parsed.success) throw new ApiError(response.status, 'internal', 'Unexpected response from the server.');
    return parsed.data;
  }

  return {
    me: () => request('GET', '/me', MeResponse),
    terms: () => request('GET', '/terms', TermsResponse),
    sections: (termId) => request('GET', `/terms/${encodeURIComponent(termId)}/sections`, SectionsResponse),
    enrollments: () => request('GET', '/me/enrollments', EnrollmentsResponse),
    grades: () => request('GET', '/me/grades', GradesResponse),
    schedule: () => request('GET', '/me/schedule', ScheduleResponse),
    teaching: () => request('GET', '/me/teaching', TeachingResponse),
    chat: (input) => request('POST', '/student-ai/chat', null, input),
  };
}
