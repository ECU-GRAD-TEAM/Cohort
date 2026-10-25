import { z } from "zod";

export const UserType = z.enum(["student", "teaching_staff", "administrator", "it_staff"]);
export type UserType = z.infer<typeof UserType>;

export const MeResponse = z.object({
  id: z.uuid(),
  email: z.string(),
  userType: UserType,
  displayName: z.string(),
  tenant: z.object({ id: z.uuid(), name: z.string() }),
  roles: z.array(z.string()),
});
export type MeResponse = z.infer<typeof MeResponse>;
