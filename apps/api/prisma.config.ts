import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  datasource: {
    url: process.env.TEST_DATABASE_URL ?? "postgresql://postgres@127.0.0.1:5432/cohort_test",
  },
});
