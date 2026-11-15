-- Add covering indexes for composite tenant-scoped foreign keys on curriculum requirement groups.
CREATE INDEX curriculum_requirement_groups_program_fk_idx
  ON public.curriculum_requirement_groups(program_id, tenant_id);
CREATE INDEX curriculum_requirement_groups_level_fk_idx
  ON public.curriculum_requirement_groups(academic_level_id, tenant_id);
CREATE INDEX curriculum_requirement_group_courses_group_fk_idx
  ON public.curriculum_requirement_group_courses(requirement_group_id, tenant_id);
CREATE INDEX curriculum_requirement_group_courses_course_fk_idx
  ON public.curriculum_requirement_group_courses(course_id, tenant_id);
