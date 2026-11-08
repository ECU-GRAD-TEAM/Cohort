import { PreviewPage } from "./PreviewPage.tsx";
import { sampleLessons, weekDays } from "./sampleData.ts";

export function SchedulePreview() {
  return (
    <PreviewPage title="Schedule">
      <div
        className="preview-timetable-scroll"
        role="region"
        aria-label="Weekly timetable"
        tabIndex={0}
      >
        <div className="preview-timetable">
          {weekDays.map((day) => (
            <section key={day} className="timetable-day" aria-label={day}>
              <h2>{day}</h2>
              {sampleLessons
                .filter((lesson) => lesson.day === day)
                .map((lesson) => (
                  <div
                    key={lesson.time + lesson.title}
                    className="timetable-slot"
                  >
                    <strong>{lesson.time}</strong> {lesson.title}
                    <span className="preview-muted">{lesson.room}</span>
                  </div>
                ))}
            </section>
          ))}
        </div>
      </div>
    </PreviewPage>
  );
}
