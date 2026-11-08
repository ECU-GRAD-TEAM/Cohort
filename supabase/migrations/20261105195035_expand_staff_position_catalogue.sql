-- Extend the staff position catalogue with additional university leadership,
-- administrative, technical, and academic support positions.
-- Position definitions remain separate from scoped system-role assignments.

INSERT INTO public.staff_positions
  (key, name, category, description, is_academic_rank, is_active)
VALUES
  ('university_president', 'University President', 'academic', 'Chief executive and academic leader of the university; normally assigned at university scope.', false, true),
  ('vice_president', 'Vice President', 'academic', 'University-level executive leadership appointment.', false, true),
  ('teaching_assistant', 'Teaching Assistant', 'academic', 'Supports teaching, tutorials, laboratories, and student learning; not an academic rank.', false, true),
  ('student_affairs_officer', 'Student Affairs Officer', 'administrative', 'Coordinates student services, welfare, activities, and student support administration.', false, true),
  ('hr_manager', 'HR Manager', 'administrative', 'Leads human resources operations and staff administration.', false, true),
  ('finance_manager', 'Finance Manager', 'administrative', 'Leads budgeting, accounting, payments, and financial operations.', false, true),
  ('quality_assurance_director', 'Quality Assurance Director', 'administrative', 'Leads institutional quality assurance, accreditation, and continuous improvement.', false, true),
  ('it_director', 'IT Director', 'technical', 'Leads university IT services, infrastructure, systems, and technical teams.', false, true),
  ('system_administrator', 'System Administrator', 'technical', 'Administers university systems, identity, access, infrastructure, and platform operations.', false, true)
ON CONFLICT (key) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  is_academic_rank = EXCLUDED.is_academic_rank,
  is_active = EXCLUDED.is_active;
