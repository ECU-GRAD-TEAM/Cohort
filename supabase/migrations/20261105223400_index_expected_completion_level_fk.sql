-- Index the optional completion-level foreign key for efficient referential checks.
CREATE INDEX IF NOT EXISTS faculty_academic_pathways_expected_completion_level_idx
  ON public.faculty_academic_pathways (expected_completion_level_id, tenant_id)
  WHERE expected_completion_level_id IS NOT NULL;
