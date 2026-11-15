export const queryKeys = {
  me: ["me"],
  terms: ["terms"],
  sections: (termId: string) => ["sections", termId],
  enrollments: ["enrollments"],
  grades: ["grades"],
} as const;
