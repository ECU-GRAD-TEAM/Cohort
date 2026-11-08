import { randomUUID } from "node:crypto";
import { Pool } from "pg";

const ownerDatabaseUrl =
  process.env.TEST_DATABASE_URL ?? "postgresql://postgres@127.0.0.1:5432/cohort_test";

/** The URL the API connects with: the `cohort_api` login role, which can do nothing until it
 * switches to `authenticated`. */
export const apiDatabaseUrl =
  process.env.TEST_API_DATABASE_URL ?? "postgresql://cohort_api@127.0.0.1:5432/cohort_test";

const shortId = () => randomUUID().slice(0, 8);

// The owner bypasses row-level security, so tests use it to seed and to inspect what the API did.
const ownerPool = new Pool({ connectionString: ownerDatabaseUrl });

export async function ownerQuery<T>(sql: string, params: unknown[] = []): Promise<T[]> {
  const result = await ownerPool.query(sql, params);
  return result.rows as T[];
}

export async function closeOwnerPool(): Promise<void> {
  await ownerPool.end();
}

/** An `auth.users` row with no app metadata: the sign-up trigger creates no `public.users` row. */
export async function createAuthOnlyUser(): Promise<string> {
  const id = randomUUID();
  await ownerQuery(`insert into auth.users (id, email) values ($1, $2)`, [
    id,
    `auth-only-${shortId()}@cohort.test`,
  ]);
  return id;
}

export type University = {
  tenantId: string;
  tenantName: string;
  termId: string;
  users: { student: string; classmate: string; latecomer: string; teacher: string; admin: string };
  courses: { cs101: string; cs201: string; ma101: string };
  offerings: { cs101: string; cs201: string; ma101: string };
  sections: { cs101: string; cs201: string; ma101: string };
};

type SeedOptions = { cs101Capacity?: number; cs101Waitlist?: number; registrationOpen?: boolean };

/**
 * Seeds one university as the database owner, with random ids: five users, one term with three
 * courses (CS201 needs CS101; MA101 is a draft), one section each, and a timetable slot for CS101.
 */
export async function seedUniversity(options: SeedOptions = {}): Promise<University> {
  const { cs101Capacity = 30, cs101Waitlist = 0, registrationOpen = true } = options;
  const k = shortId();

  const tenantId = randomUUID();
  const tenantName = `University ${k}`;
  const termId = randomUUID();
  const facultyId = randomUUID();
  const departmentId = randomUUID();
  const buildingId = randomUUID();
  const roomId = randomUUID();
  const users = {
    student: randomUUID(),
    classmate: randomUUID(),
    latecomer: randomUUID(),
    teacher: randomUUID(),
    admin: randomUUID(),
  };
  const courses = { cs101: randomUUID(), cs201: randomUUID(), ma101: randomUUID() };
  const offerings = { cs101: randomUUID(), cs201: randomUUID(), ma101: randomUUID() };
  const sections = { cs101: randomUUID(), cs201: randomUUID(), ma101: randomUUID() };

  const accounts = [
    { key: "student", name: "Sara Student", type: "student" },
    { key: "classmate", name: "Samir Student", type: "student" },
    { key: "latecomer", name: "Laila Late", type: "student" },
    { key: "teacher", name: "Tariq Teacher", type: "teaching_staff" },
    { key: "admin", name: "Ada Admin", type: "administrator" },
  ] as const;
  const catalogue = [
    { key: "cs101", code: "CS101", title: "Programming I", credits: 3.5, status: "published", capacity: cs101Capacity, waitlist: cs101Waitlist },
    { key: "cs201", code: "CS201", title: "Programming II", credits: 3, status: "published", capacity: 30, waitlist: 0 },
    { key: "ma101", code: "MA101", title: "Calculus I", credits: 3, status: "draft", capacity: 30, waitlist: 0 },
  ] as const;

  // One transaction, so a failed seed leaves nothing behind.
  const client = await ownerPool.connect();
  try {
    await client.query("begin");

    await client.query(
      `insert into public.tenants (id, slug, name, data_region) values ($1, $2, $3, 'eu-west-1')`,
      [tenantId, `t-${k}`, tenantName],
    );

    // Accounts are provisioned through auth.users; the sign-up trigger creates public.users.
    for (const account of accounts) {
      await client.query(
        `insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
         values ($1, $2, $3::jsonb, $4::jsonb)`,
        [
          users[account.key],
          `${account.key}-${k}@cohort.test`,
          JSON.stringify({ tenant_id: tenantId, user_type: account.type }),
          JSON.stringify({ full_name: account.name }),
        ],
      );
    }

    await client.query(
      `insert into public.faculties (id, tenant_id, code, name) values ($1, $2, 'ENG', 'Engineering')`,
      [facultyId, tenantId],
    );
    await client.query(
      `insert into public.departments (id, tenant_id, faculty_id, code, name)
       values ($1, $2, $3, 'CS', 'Computer Science')`,
      [departmentId, tenantId, facultyId],
    );
    await client.query(
      `insert into public.buildings (id, tenant_id, code, name) values ($1, $2, 'B1', 'Main Building')`,
      [buildingId, tenantId],
    );
    await client.query(
      `insert into public.rooms (id, tenant_id, building_id, code, room_type)
       values ($1, $2, $3, '101', 'lecture_hall')`,
      [roomId, tenantId, buildingId],
    );

    // Registration opens a day ago and closes in a week; closed, it opens tomorrow.
    await client.query(
      `insert into public.terms
         (id, tenant_id, code, name, starts_on, ends_on, registration_opens_at, registration_closes_at)
       values ($1, $2, $3, 'Fall 2026', current_date - 7, current_date + 90,
               now() + $4::interval, now() + $5::interval)`,
      [termId, tenantId, `T-${k}`, registrationOpen ? "-1 day" : "1 day", registrationOpen ? "7 days" : "8 days"],
    );

    for (const course of catalogue) {
      await client.query(
        `insert into public.courses (id, tenant_id, department_id, code, title, credit_hours)
         values ($1, $2, $3, $4, $5, $6)`,
        [courses[course.key], tenantId, departmentId, course.code, course.title, course.credits],
      );
      await client.query(
        `insert into public.course_offerings (id, tenant_id, course_id, term_id, status)
         values ($1, $2, $3, $4, $5)`,
        [offerings[course.key], tenantId, courses[course.key], termId, course.status],
      );
      await client.query(
        `insert into public.sections (id, tenant_id, offering_id, code, capacity, waitlist_capacity)
         values ($1, $2, $3, 'L1', $4, $5)`,
        [sections[course.key], tenantId, offerings[course.key], course.capacity, course.waitlist],
      );
    }

    await client.query(
      `insert into public.course_prerequisites (course_id, prerequisite_course_id, tenant_id)
       values ($1, $2, $3)`,
      [courses.cs201, courses.cs101, tenantId],
    );
    await client.query(
      `insert into public.section_instructors (section_id, user_id, tenant_id) values ($1, $2, $3)`,
      [sections.cs101, users.teacher, tenantId],
    );
    // Weekday 7 (Sunday), 09:05 to 10:30.
    await client.query(
      `insert into public.timetable_entries
         (tenant_id, section_id, room_id, weekday, starts_at, ends_at, valid_from, valid_until)
       values ($1, $2, $3, 7, '09:05', '10:30', current_date - 7, current_date + 90)`,
      [tenantId, sections.cs101, roomId],
    );

    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }

  return { tenantId, tenantName, termId, users, courses, offerings, sections };
}
