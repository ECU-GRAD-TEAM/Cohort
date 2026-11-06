-- Programme specializations, their course mappings, and auditable student selection history.
CREATE TABLE public.specializations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL,
 program_id uuid NOT NULL,
 code text NOT NULL,
 name text NOT NULL,
 description text,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT specializations_program_code_key UNIQUE(program_id,tenant_id,code),
 CONSTRAINT specializations_id_tenant_key UNIQUE(id,tenant_id),
 CONSTRAINT specializations_id_program_tenant_key UNIQUE(id,program_id,tenant_id),
 CONSTRAINT specializations_program_tenant_fkey FOREIGN KEY(program_id,tenant_id)
   REFERENCES public.programs(id,tenant_id) ON DELETE CASCADE
);
CREATE INDEX specializations_tenant_program_active_idx ON public.specializations(tenant_id,program_id,is_active);

CREATE TABLE public.specialization_courses (
 tenant_id uuid NOT NULL,
 program_id uuid NOT NULL,
 specialization_id uuid NOT NULL,
 course_id uuid NOT NULL,
 is_required boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(specialization_id,course_id),
 CONSTRAINT specialization_courses_specialization_fkey
   FOREIGN KEY(specialization_id,program_id,tenant_id)
   REFERENCES public.specializations(id,program_id,tenant_id) ON DELETE CASCADE,
 CONSTRAINT specialization_courses_course_fkey
   FOREIGN KEY(course_id,tenant_id) REFERENCES public.courses(id,tenant_id) ON DELETE CASCADE
);
CREATE INDEX specialization_courses_tenant_course_idx ON public.specialization_courses(tenant_id,course_id);

CREATE TABLE public.student_specialization_selections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL,
 student_id uuid NOT NULL,
 program_id uuid NOT NULL,
 specialization_id uuid NOT NULL,
 status text NOT NULL DEFAULT 'pending'
   CHECK(status IN ('pending','approved','rejected','withdrawn','cancelled')),
 requested_at timestamptz NOT NULL DEFAULT now(),
 reviewed_by uuid,
 reviewed_at timestamptz,
 decision_note text,
 starts_on date,
 ends_on date,
 CONSTRAINT student_specialization_selections_student_fkey
   FOREIGN KEY(student_id,tenant_id) REFERENCES public.users(id,tenant_id) ON DELETE CASCADE,
 CONSTRAINT student_specialization_selections_program_fkey
   FOREIGN KEY(program_id,tenant_id) REFERENCES public.programs(id,tenant_id) ON DELETE RESTRICT,
 CONSTRAINT student_specialization_selections_specialization_fkey
   FOREIGN KEY(specialization_id,program_id,tenant_id)
   REFERENCES public.specializations(id,program_id,tenant_id) ON DELETE RESTRICT,
 CONSTRAINT student_specialization_selections_reviewer_fkey
   FOREIGN KEY(reviewed_by,tenant_id) REFERENCES public.users(id,tenant_id) ON DELETE RESTRICT,
 CHECK(ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
 CHECK((status NOT IN ('approved','rejected')) OR reviewed_at IS NOT NULL)
);
CREATE INDEX student_specialization_selections_student_time_idx
 ON public.student_specialization_selections(tenant_id,student_id,requested_at DESC);
CREATE INDEX student_specialization_selections_program_status_idx
 ON public.student_specialization_selections(tenant_id,program_id,status);
CREATE INDEX student_specialization_selections_specialization_idx
 ON public.student_specialization_selections(tenant_id,specialization_id);

ALTER TABLE public.specializations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.specialization_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_specialization_selections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant members read specializations" ON public.specializations
 FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()));
CREATE POLICY "academic managers manage specializations" ON public.specializations
 FOR ALL TO authenticated
 USING(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=specializations.program_id AND p.tenant_id=specializations.tenant_id))))
 WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=specializations.program_id AND p.tenant_id=specializations.tenant_id))));

CREATE POLICY "tenant members read specialization courses" ON public.specialization_courses
 FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()));
CREATE POLICY "academic managers manage specialization courses" ON public.specialization_courses
 FOR ALL TO authenticated
 USING(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=specialization_courses.program_id AND p.tenant_id=specialization_courses.tenant_id))))
 WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=specialization_courses.program_id AND p.tenant_id=specialization_courses.tenant_id))));

CREATE POLICY "tenant members read specialization selections" ON public.student_specialization_selections
 FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()));
CREATE POLICY "academic managers manage specialization selections" ON public.student_specialization_selections
 FOR ALL TO authenticated
 USING(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=student_specialization_selections.program_id AND p.tenant_id=student_specialization_selections.tenant_id))))
 WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND
   (SELECT private.has_permission_for_department('academic.manage',
     (SELECT p.department_id FROM public.programs p WHERE p.id=student_specialization_selections.program_id AND p.tenant_id=student_specialization_selections.tenant_id))));
