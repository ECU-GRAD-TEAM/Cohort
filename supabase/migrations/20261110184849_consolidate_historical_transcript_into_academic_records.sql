-- Consolidate verified historical transcript records into the existing academic model.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.student_transcript_imports WHERE status='verified') <> 1
     OR (SELECT count(*) FROM public.student_transcript_terms) <> 8
     OR (SELECT count(*) FROM public.student_transcript_entries) <> 49 THEN
    RAISE EXCEPTION 'Unexpected transcript source counts; aborting';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.student_transcript_entries e
    LEFT JOIN public.courses c ON c.id=e.course_id AND c.tenant_id=e.tenant_id
    WHERE c.id IS NULL
  ) THEN RAISE EXCEPTION 'Unresolved catalogue courses'; END IF;
END $$;

ALTER TABLE public.enrollments
  ALTER COLUMN section_id DROP NOT NULL,
  ALTER COLUMN offering_id DROP NOT NULL,
  ADD COLUMN course_id uuid,
  ADD COLUMN term_id uuid,
  ADD COLUMN credit_hours_attempted numeric(7,2),
  ADD COLUMN quality_points numeric(9,2),
  ADD COLUMN record_origin text NOT NULL DEFAULT 'live';

ALTER TABLE public.enrollments
  ADD CONSTRAINT enrollments_course_id_tenant_id_fkey FOREIGN KEY(course_id,tenant_id) REFERENCES public.courses(id,tenant_id),
  ADD CONSTRAINT enrollments_term_id_tenant_id_fkey FOREIGN KEY(term_id,tenant_id) REFERENCES public.terms(id,tenant_id),
  ADD CONSTRAINT enrollments_record_origin_check CHECK(record_origin IN ('live','imported_transcript')),
  ADD CONSTRAINT enrollments_record_shape_check CHECK (
    (record_origin='imported_transcript' AND offering_id IS NULL AND section_id IS NULL
      AND course_id IS NOT NULL AND term_id IS NOT NULL AND credit_hours_attempted IS NOT NULL
      AND final_grade_letter IS NOT NULL AND final_grade_points IS NOT NULL AND quality_points IS NOT NULL)
    OR (record_origin='live' AND offering_id IS NOT NULL AND section_id IS NOT NULL)
  );

CREATE UNIQUE INDEX enrollments_historical_student_course_term_uidx
 ON public.enrollments(tenant_id,student_id,course_id,term_id)
 WHERE record_origin='imported_transcript';
CREATE INDEX enrollments_historical_student_term_idx
 ON public.enrollments(tenant_id,student_id,term_id)
 WHERE record_origin='imported_transcript';

ALTER TABLE public.gpa_snapshots
 ADD COLUMN term_quality_points numeric(9,2),
 ADD COLUMN cumulative_quality_points numeric(9,2),
 ADD COLUMN snapshot_source text NOT NULL DEFAULT 'computed',
 ADD CONSTRAINT gpa_snapshots_source_check CHECK(snapshot_source IN ('computed','imported_transcript'));

CREATE OR REPLACE FUNCTION private.enforce_ecu_repeat_course_policy()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE v_course_id uuid; v_is_repeat boolean;
BEGIN
  IF NEW.record_origin='imported_transcript' THEN RETURN NEW; END IF;
  SELECT o.course_id INTO v_course_id FROM public.course_offerings o
   WHERE o.id=NEW.offering_id AND o.tenant_id=NEW.tenant_id;
  IF v_course_id IS NULL THEN
    RAISE EXCEPTION 'Course offering was not found for this enrollment' USING errcode='foreign_key_violation';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.enrollments prior
    JOIN public.course_offerings po ON po.id=prior.offering_id AND po.tenant_id=prior.tenant_id
    WHERE prior.student_id=NEW.student_id AND prior.tenant_id=NEW.tenant_id
      AND po.course_id=v_course_id AND prior.id<>NEW.id
      AND prior.status NOT IN ('dropped'::public.enrollment_status,'withdrawn'::public.enrollment_status,'waitlisted'::public.enrollment_status)
  ) INTO v_is_repeat;
  IF v_is_repeat AND NEW.final_grade_points IS NOT NULL AND NEW.final_grade_points>3.3 THEN
    NEW.final_grade_letter:='B+'; NEW.final_grade_points:=3.3;
  END IF;
  RETURN NEW;
END;
$function$;

INSERT INTO public.terms(tenant_id,code,name,status,term_kind,sequence_number)
SELECT t.tenant_id,
 upper(regexp_replace(split_part(t.term_name,' ',2),'/','-','g')) || '-' || upper(split_part(t.term_name,' ',1)),
 t.term_name,'completed'::public.term_status,
 lower(split_part(t.term_name,' ',1))::public.academic_term_kind,t.term_order
FROM public.student_transcript_terms t
WHERE NOT EXISTS(SELECT 1 FROM public.terms x WHERE x.tenant_id=t.tenant_id AND x.name=t.term_name);

INSERT INTO public.enrollments(
 tenant_id,student_id,course_id,term_id,status,enrolled_at,status_changed_at,
 credit_hours_attempted,final_grade_letter,final_grade_points,quality_points,record_origin
)
SELECT e.tenant_id,i.student_id,e.course_id,tm.id,
 CASE WHEN e.is_passed THEN 'completed'::public.enrollment_status ELSE 'failed'::public.enrollment_status END,
 now(),now(),e.credit_hours,e.grade_letter,e.grade_points,e.quality_points,'imported_transcript'
FROM public.student_transcript_entries e
JOIN public.student_transcript_imports i ON i.id=e.import_id
JOIN public.student_transcript_terms st ON st.id=e.term_id
JOIN public.terms tm ON tm.tenant_id=st.tenant_id AND tm.name=st.term_name
WHERE i.status='verified';

INSERT INTO public.gpa_snapshots(
 tenant_id,student_id,term_id,term_gpa,cgpa,credits_attempted,credits_earned,
 term_quality_points,cumulative_quality_points,snapshot_source
)
SELECT i.tenant_id,i.student_id,tm.id,st.term_gpa,st.cumulative_gpa,
 st.registered_credit_hours,st.cumulative_passed_credit_hours,
 round(st.term_gpa*st.registered_credit_hours,2),st.cumulative_quality_points,'imported_transcript'
FROM public.student_transcript_terms st
JOIN public.student_transcript_imports i ON i.id=st.import_id
JOIN public.terms tm ON tm.tenant_id=st.tenant_id AND tm.name=st.term_name
WHERE i.status='verified';

CREATE POLICY "registrars manage historical enrolments"
ON public.enrollments FOR ALL TO authenticated
USING(record_origin='imported_transcript' AND tenant_id=(SELECT private.tenant_id())
 AND private.has_permission_for_student('enrollment.manage',student_id))
WITH CHECK(record_origin='imported_transcript' AND tenant_id=(SELECT private.tenant_id())
 AND private.has_permission_for_student('enrollment.manage',student_id));

DO $$
BEGIN
 IF (SELECT count(*) FROM public.enrollments WHERE record_origin='imported_transcript')<>49
 OR (SELECT count(*) FROM public.gpa_snapshots WHERE snapshot_source='imported_transcript')<>8
 OR (SELECT sum(credit_hours_attempted) FROM public.enrollments WHERE record_origin='imported_transcript')<>145
 OR (SELECT sum(quality_points) FROM public.enrollments WHERE record_origin='imported_transcript')<>517.50
 THEN RAISE EXCEPTION 'Historical data verification failed'; END IF;
END $$;

DROP TABLE public.student_transcript_entries;
DROP TABLE public.student_transcript_terms;
DROP TABLE public.student_transcript_imports;
