import React from 'react';
import { BookOpen, Loader2 } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

/**
 * What a page shows in place of course content when the account has no courses: still loading,
 * failed to load (with a retry), or genuinely none yet.
 */
export function NoCourses({ compact = false }) {
  const { t, role, live } = useCohort();
  const isStaff = role === 'Academic Staff';
  const pad = compact ? 'p-4' : 'p-8';

  if (live.status === 'loading') {
    return (
      <div className={`flex items-center justify-center gap-2 rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] ${pad} text-sm font-semibold text-[#6E645D]`} role="status">
        <Loader2 className="h-4 w-4 animate-spin text-[#B81104]" aria-hidden="true" />
        {t('Loading your courses…', 'جارٍ تحميل مقرراتك…')}
      </div>
    );
  }
  if (live.status === 'error') {
    return (
      <div className={`rounded-2xl border border-[#C93636]/30 bg-[#FFE9E5] ${pad} text-sm text-[#8A1F1F]`} role="alert">
        <p className="font-bold">{t('Your courses could not be loaded.', 'تعذّر تحميل مقرراتك.')}</p>
        <p className="mt-1">{live.error?.message}</p>
        <button
          type="button"
          onClick={live.reload}
          className="mt-3 rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
        >
          {t('Try again', 'حاول مرة أخرى')}
        </button>
      </div>
    );
  }
  return (
    <div className={`rounded-2xl border border-dashed border-[#E8E3D9] bg-[#FCFBF6] ${pad} text-center`}>
      <BookOpen className="mx-auto h-6 w-6 text-[#B81104]" aria-hidden="true" />
      <p className="mt-2 text-sm font-bold text-[#302521]">
        {isStaff ? t('No sections assigned yet', 'لا توجد شعب مسندة بعد') : t('No courses yet', 'لا توجد مقررات بعد')}
      </p>
      <p className="mt-1 text-xs text-[#6E645D]">
        {isStaff
          ? t(
              'When your department assigns you to teach a section, it appears here.',
              'عندما يسند إليك قسمك تدريس شعبة، ستظهر هنا.'
            )
          : t(
              'When the registrar enrols you in a course, it appears here with your sections and grades.',
              'عندما يسجلك المسجل في مقرر، سيظهر هنا مع شعبك ودرجاتك.'
            )}
      </p>
    </div>
  );
}
