import React from 'react';
import { useCohort } from '../../context/CohortContext';

/** Marks a block that still shows sample data rather than the university's records. */
export function PreviewTag() {
  const { t } = useCohort();
  return (
    <span
      className="rounded-md border border-[#E9DBA9] bg-[#FFF4D4] px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-[#80540D]"
      title={t('Sample data: not connected to your university yet.', 'بيانات تجريبية: غير مرتبطة بجامعتك بعد.')}
    >
      {t('Preview', 'معاينة')}
    </span>
  );
}
