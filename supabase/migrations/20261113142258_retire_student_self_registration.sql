-- Students no longer register themselves: since 20261112185500 an enrolment is per course
-- offering, and registrars create it and assign the student to class meetings
-- (public.student_meetings). enroll_in_section and drop_section still wrote the removed
-- enrollments.section_id, so every call failed with "column does not exist". They now refuse with
-- a message that says why. Their signatures and grants are kept so that callers get this message
-- rather than "function does not exist"; dropping them is a separate decision.

CREATE OR REPLACE FUNCTION public.enroll_in_section(p_section uuid)
 RETURNS public.enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Students no longer register themselves; the registrar enrols students and assigns their class meetings'
    USING ERRCODE = 'feature_not_supported';
END;
$function$;

CREATE OR REPLACE FUNCTION public.drop_section(p_section uuid)
 RETURNS public.enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Students no longer drop sections themselves; ask the registrar to change your enrolment'
    USING ERRCODE = 'feature_not_supported';
END;
$function$;
