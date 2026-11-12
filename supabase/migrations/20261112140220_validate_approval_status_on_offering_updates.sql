-- Require an approval snapshot whenever the offering approval state changes.
drop trigger if exists course_offerings_require_approved_grading_config on public.course_offerings;
create trigger course_offerings_require_approved_grading_config
before insert or update of status, grading_config_status on public.course_offerings
for each row execute function private.require_approved_grading_config_before_publish();
