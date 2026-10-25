import {
  ApiErrorBody,
  EnrollmentChange,
  EnrollmentsResponse,
  GradesResponse,
  MeResponse,
  SectionsResponse,
  TermsResponse,
  type ApiErrorCode,
} from "@cohort/contracts";

const GENERIC_MESSAGE = "Something went wrong. Please try again.";
const UNEXPECTED_MESSAGE = "Unexpected response from the server.";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ApiErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export type ApiClient = {
  getMe(): Promise<MeResponse>;
  getTerms(): Promise<TermsResponse>;
  getSections(termId: string): Promise<SectionsResponse>;
  getMyEnrollments(): Promise<EnrollmentsResponse>;
  enroll(sectionId: string): Promise<EnrollmentChange>;
  drop(sectionId: string): Promise<EnrollmentChange>;
  getMyGrades(): Promise<GradesResponse>;
};

export type ApiClientOptions = {
  baseUrl: string;
  getAccessToken: () => Promise<string | null>;
  onUnauthorized?: () => void;
};

// The part of a Zod schema the client relies on, so the web app needs no direct Zod import.
type Schema<T> = {
  safeParse(data: unknown): { success: true; data: T } | { success: false };
};

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return undefined;
  }
}

export function createApiClient({ baseUrl, getAccessToken, onUnauthorized }: ApiClientOptions): ApiClient {
  async function request<T>(method: string, path: string, schema: Schema<T>, body?: unknown): Promise<T> {
    const headers: Record<string, string> = { accept: "application/json" };
    const token = await getAccessToken();
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";

    let response: Response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError(0, "internal", GENERIC_MESSAGE);
    }

    // Any 401 reaches onUnauthorized, whatever the body holds.
    if (response.status === 401) onUnauthorized?.();

    const payload = await readJson(response);

    if (!response.ok) {
      const failure = ApiErrorBody.safeParse(payload);
      if (failure.success) {
        throw new ApiError(response.status, failure.data.error.code, failure.data.error.message);
      }
      throw new ApiError(response.status, "internal", GENERIC_MESSAGE);
    }

    const parsed = schema.safeParse(payload);
    if (!parsed.success) throw new ApiError(response.status, "internal", UNEXPECTED_MESSAGE);
    return parsed.data;
  }

  return {
    getMe: () => request("GET", "/me", MeResponse),
    getTerms: () => request("GET", "/terms", TermsResponse),
    getSections: (termId) => request("GET", `/terms/${encodeURIComponent(termId)}/sections`, SectionsResponse),
    getMyEnrollments: () => request("GET", "/me/enrollments", EnrollmentsResponse),
    enroll: (sectionId) => request("POST", "/enrollments", EnrollmentChange, { sectionId }),
    drop: (sectionId) => request("DELETE", `/enrollments/${encodeURIComponent(sectionId)}`, EnrollmentChange),
    getMyGrades: () => request("GET", "/me/grades", GradesResponse),
  };
}
