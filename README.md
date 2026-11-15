# UniFlow university workspace

Responsive browser-local implementation of the university SaaS design documents. Updated with Milano Red #B81104, Lemon Chiffon #FFFACD, Inter and Noto Sans Arabic, focused navigation, consistent SVG navigation icons, larger touch targets and Arabic navigation with RTL layout.

## Run
Serve `dist/` with a static server. No build step is needed. Run `node --check dist/app.js`, `node --check dist/workspace.js`, and `node tests/validation.mjs` for source checks.

## Implemented local workflows
- Course workspace tabs for materials, assignments, quizzes, grades, attendance, announcements and discussions.
- Materials, versioning, release dates, text previews and file downloads. Attachments stored in IndexedDB with a 10 MB limit.
- Assignment authoring, instructions, rubric, model-answer release, local submissions and receipts, one resubmission before deadline.
- Quiz builder and question bank with MCQ, true/false, matching, essay and problem solving; browser timer, answer autosave, attempt limits, objective scoring and written-answer review.
- Explicit draft, approved and published grade states, confirmation before publication and local change history.
- Name-entry attendance sessions, pending requests and instructor status confirmation. No fake QR verification.
- Timetable clash and room-capacity checks, academic calendars, exam seat release gating and iCalendar export.
- Local directory creation/editing and validated CSV imports; academic structure and course offerings; enrolment validation and waiting lists.
- Requests with categories, priorities, response targets, owner assignment, internal notes, replies and resolution history.
- Local messages, appointment booking/cancellation, notifications, preferences, event registration, lost-and-found items and an illustrative campus directory.
- Incidents with owner, severity, evidence, history and resolution notes; sample service/log/AI telemetry views.
- Manually confirmed workflow-rule runs; proposed AI budgets and preferences; local audit and CSV/data export.
- Prepared assistant answers with inspectable sample sources and feedback controls. No live LLM.

## Verification
- JavaScript syntax checks passed.
- Eleven business-rule assertions passed (duplicate emails, capacity, prerequisite self-reference, schedule overlaps and adjacent slots, incident notes, question keys and quoted CSV).
- Browser-confirmed quiz flow scored 2/2 objective answers and left essay in Needs review.
- Browser-confirmed grade approval remained unpublished.
- Browser-confirmed overlapping timetable request rejected while retaining input.
- Browser-confirmed incident saved with Resolved state and notes.
- Desktop and 390px Arabic RTL mobile layout visually inspected.
- Final support-form browser check could not run after browser tooling denied access; do not claim every interaction is tested. A broad screen smoke-test tool timed out before its final report, so it is not counted as a completed test suite.

## Remaining production work
This is not a production multi-tenant university service. Role switching is a visual preview, not authorization. All information is sample data stored in a visitor's browser. Do not enter real educational or personal records. No university SSO/MFA, secure account recovery, server permission enforcement, tenant isolation, live AI/RAG/predictive models, real messaging, push/email, finance integration, live monitoring, secure QR check-in, server-authoritative exams, server uploads, cross-device sync or scheduled background automation is connected. Some Arabic content remains English; Arabic navigation and RTL are provided, not a complete translation audit. Accessibility improvements are implemented but WCAG conformance has not been independently audited. Browser file persistence is not cloud backup and offline app-shell caching is not implemented.

The in-app Feature status screen makes these boundaries visible to users.

## Floating dock navigation update
The sidebar and hamburger drawer are hidden at all breakpoints. The role selector and brand move to the header. A five-destination floating bottom dock adapts to the selected role, supports RTL, exposes aria-current and keyboard focus, and replaces More with Chats, opening Messages. Safe-area offsets and footer padding reserve room for the dock. Verified JavaScript syntax and existing business-rule assertions; browser visual QA was unavailable in this pass.

## Academic Staff and IT dashboards — November 2026
Dedicated responsive dashboards in `dist/dashboards.js` and `dist/dashboards.css`, loaded after the existing workspace. The Academic Staff display label preserves the internal Teaching staff role for stored data compatibility.

Academic dashboard: grade/written-response review queue, approved publication count, course cards, published teaching sessions, materials, assignments and quiz creation shortcuts, local grade publication progress and a teaching assistant entry point.

IT dashboard: explicit sample service snapshot, dynamic local incident and IT ticket counts, incident investigation, sample latency comparison, local activity and links to logs/storage/security/AI preferences. Sample telemetry is deliberately separate from incident workflow state.

Validation: JavaScript syntax and existing 11 business-rule assertions pass. Browser-verified both desktop dashboards, 390px mobile viewport and Arabic RTL academic layout (no horizontal overflow), grade review, assignment creation, material creation, incident details and mobile incident creation forms. No end-to-end university integration or live telemetry is claimed.

## Profile, notifications and appeals update
The header profile picture opens a menu for help, notifications, profile, settings and chats. Profile editing keeps email, programme and academic year read-only while allowing display name and phone changes. Quiz and assignment notifications can be toggled independently. The schedule page places a class timetable on the right with room, duration and lecturer details. Submitted quizzes offer an appeal action that records a local manual review request and adds it to the Academic Staff queue.
