-- Restore the permission catalogue removed from public.permissions.
-- Preserve role assignments: this migration restores definitions only.
INSERT INTO public.permissions (key, description) VALUES
  ('tenant.settings.manage', 'Edit university-wide settings'),
  ('users.manage', 'Create, suspend and archive accounts; assign roles'),
  ('academic.manage', 'Manage faculties, departments, programmes, courses, terms, sections, rooms and timetables'),
  ('enrollment.manage', 'Manage registrations, waiting lists, withdrawals and advisor assignments'),
  ('grades.manage', 'Manage grade scales and academic standing'),
  ('exams.manage', 'Schedule exam sessions, assign halls and seats'),
  ('announcements.publish', 'Publish university-wide, department and role announcements'),
  ('events.manage', 'Create and manage activities and events'),
  ('surveys.manage', 'Create university-wide surveys and read raw responses'),
  ('support.manage', 'Triage and resolve tickets in every queue'),
  ('workflows.manage', 'Define workflow automations and approve their runs'),
  ('campus.manage', 'Manage the campus map and moderate lost and found'),
  ('emergency.publish', 'Send emergency notifications'),
  ('ai.settings.manage', 'Enable AI features, choose models, set budgets and prompt templates'),
  ('ai.knowledge.manage', 'Manage the institutional documents the assistants answer from'),
  ('analytics.view', 'View aggregate analytics and dashboards'),
  ('records.break_glass', 'Open an audited, time-limited view of an individual student record'),
  ('audit.read', 'Read audit and data access logs'),
  ('retention.manage', 'Manage retention schedules and legal holds'),
  ('ops.manage', 'Manage incidents and monitoring'),
  ('appointments.manage', 'Create, update, end and revoke personnel appointments within the assigned scope')
ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description;