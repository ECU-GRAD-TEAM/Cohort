import React, { useEffect, useState } from 'react';
import { Lock, Save, UserCheck, Building2, Mail, Phone, Award, ArrowRight } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { ProfileHubNav } from '../profile/ProfileHubNav';

export function ProfilePage() {
  const { role, lang, t, profile, updateProfile, navigate } = useCohort();

  const [name, setName] = useState(profile.name);
  const [phone, setPhone] = useState(profile.phone || '');
  const [officeHoursNote, setOfficeHoursNote] = useState(profile.officeHoursNote || '');

  useEffect(() => {
    setName(profile.name);
    setPhone(profile.phone || '');
    setOfficeHoursNote(profile.officeHoursNote || '');
  }, [profile]);

  const initials = profile.name
    .split(' ')
    .filter(Boolean)
    .map((p) => p[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!name.trim()) return;
    if (role === 'Academic Staff') {
      updateProfile({
        name: name.trim(),
        phone: phone.trim(),
        officeHoursNote: officeHoursNote.trim(),
      });
    } else {
      updateProfile({
        name: name.trim(),
        phone: phone.trim(),
      });
    }
  };

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {role === 'Student'
              ? t('STUDENT PROFILE HUB', 'مركز ملف الطالب')
              : t('ACADEMIC STAFF PROFILE HUB', 'مركز ملف هيئة التدريس')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {t('Profile & Academic Identity', 'الملف الشخصي والهوية الأكاديمية')}
          </h1>
          <p className="mt-1 text-sm text-[#6E645D]">
            {t(
              'Update your contact information. Institutional academic records remain locked and dimmed.',
              'حدّث بيانات التواصل الخاصة بك. تبقى السجلات الأكاديمية المؤسسية مقفلة وباهتة لحمايتها.'
            )}
          </p>
        </div>

        <button
          type="button"
          onClick={() => navigate('academic-affairs')}
          className="inline-flex min-h-[42px] items-center gap-2 rounded-xl bg-[#FFFACD] px-4 py-2 text-xs font-bold text-[#B81104] border border-[#E9DBA9] transition hover:bg-[#FFF2B5]"
        >
          <span>{t('Open Academic Affairs & Analytics', 'فتح الشؤون الأكاديمية والتحليلات')}</span>
          <ArrowRight className="h-4 w-4 rtl:rotate-180" aria-hidden="true" />
        </button>
      </div>

      <ProfileHubNav />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        {/* Summary Identity Card */}
        <div className="cohort-card p-6 lg:col-span-4 space-y-5">
          <div className="flex items-center gap-4">
            <div className="grid h-16 w-16 shrink-0 place-items-center rounded-2xl bg-[#B81104] text-2xl font-extrabold text-[#FFFACD]">
              {initials}
            </div>
            <div className="min-w-0">
              <h2 className="truncate text-lg font-bold text-[#302521]">
                {lang === 'ar' && profile.nameAr ? profile.nameAr : profile.name}
              </h2>
              <p className="text-xs font-semibold text-[#B81104]">{profile.id}</p>
              <span className="mt-1.5 inline-flex items-center gap-1 rounded-md bg-[#E8F5EC] px-2 py-0.5 text-[11px] font-semibold text-[#16845B]">
                <UserCheck className="h-3.5 w-3.5" aria-hidden="true" />
                {role === 'Student'
                  ? lang === 'ar'
                    ? profile.standingAr
                    : profile.standing
                  : lang === 'ar'
                    ? profile.rankAr
                    : profile.rank}
              </span>
            </div>
          </div>

          <div className="space-y-3 border-t border-[#E8E3D9] pt-4 text-xs">
            <div className="flex items-center gap-2.5 text-[#6E645D]">
              <Mail className="h-4 w-4 shrink-0 text-[#B81104]" aria-hidden="true" />
              <span className="truncate">{profile.email}</span>
            </div>
            <div className="flex items-center gap-2.5 text-[#6E645D]">
              <Phone className="h-4 w-4 shrink-0 text-[#B81104]" aria-hidden="true" />
              <span className="tabular-nums">{phone || t('Not set', 'غير مسجل')}</span>
            </div>
            <div className="flex items-center gap-2.5 text-[#6E645D]">
              <Building2 className="h-4 w-4 shrink-0 text-[#B81104]" aria-hidden="true" />
              <span>
                {role === 'Student'
                  ? lang === 'ar'
                    ? profile.programmeAr
                    : profile.programme
                  : lang === 'ar'
                    ? profile.departmentAr
                    : profile.department}
              </span>
            </div>
            <div className="flex items-center gap-2.5 text-[#6E645D]">
              <Award className="h-4 w-4 shrink-0 text-[#B81104]" aria-hidden="true" />
              <span>
                {role === 'Student'
                  ? `${t('Academic Advisor:', 'المرشد الأكاديمي:')} ${
                      lang === 'ar' ? profile.advisorAr : profile.advisor
                    }`
                  : `${t('Office Room:', 'غرفة المكتب:')} ${
                      lang === 'ar' ? profile.officeRoomAr : profile.officeRoom
                    }`}
              </span>
            </div>
          </div>

          <div className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/65 p-3.5 text-xs text-[#302521]">
            <p className="font-bold text-[#B81104]">
              {t('Need to update a locked record?', 'تحتاج لتعديل بيانات مقفلة؟')}
            </p>
            <p className="mt-1 text-[#6E645D] leading-relaxed">
              {t(
                'Programme, academic year, and university email are verified by the Registrar. Submit an official petition inside Academic Affairs.',
                'البرنامج الدراسي والسنة الأكاديمية والبريد الجامعي مُعتمدة من المسجل. قدّم طلبًا رسميًا من الشؤون الأكاديمية.'
              )}
            </p>
          </div>
        </div>

        {/* Editable + Dimmed Form (#9) */}
        <form onSubmit={handleSubmit} className="cohort-card p-6 lg:col-span-8 space-y-6">
          <div>
            <h2 className="text-base font-bold text-[#302521]">
              {t('Editable Contact Details', 'بيانات التواصل القابلة للتعديل')}
            </h2>
            <p className="mt-0.5 text-xs text-[#6E645D]">
              {t('Changes apply immediately in your local Cohort workspace.', 'تُحفظ التعديلات مباشرة في مساحة عملك.')}
            </p>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="profile-display-name" className="block text-xs font-semibold text-[#302521] mb-1.5">
                {t('Display Name', 'الاسم المعروض')} *
              </label>
              <input
                id="profile-display-name"
                type="text"
                required
                maxLength={100}
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full min-h-[44px] rounded-xl border border-[#D6CFC1] bg-white px-3.5 py-2 text-sm text-[#302521] focus:border-[#B81104] focus:outline-none"
              />
            </div>

            <div>
              <label htmlFor="profile-phone" className="block text-xs font-semibold text-[#302521] mb-1.5">
                {t('Phone Number', 'رقم الهاتف')}
              </label>
              <input
                id="profile-phone"
                type="tel"
                maxLength={30}
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+20 100 000 0000"
                className="w-full min-h-[44px] rounded-xl border border-[#D6CFC1] bg-white px-3.5 py-2 text-sm text-[#302521] tabular-nums focus:border-[#B81104] focus:outline-none"
              />
            </div>

            {role === 'Academic Staff' ? (
              <div className="sm:col-span-2">
                <label htmlFor="profile-office-hours" className="block text-xs font-semibold text-[#302521] mb-1.5">
                  {t('Office Hours & Consultation Availability', 'الساعات المكتبية ومواعيد الاستشارة')}
                </label>
                <input
                  id="profile-office-hours"
                  type="text"
                  maxLength={160}
                  value={officeHoursNote}
                  onChange={(e) => setOfficeHoursNote(e.target.value)}
                  className="w-full min-h-[44px] rounded-xl border border-[#D6CFC1] bg-white px-3.5 py-2 text-sm text-[#302521] focus:border-[#B81104] focus:outline-none"
                />
              </div>
            ) : null}
          </div>

          <div className="border-t border-[#E8E3D9] pt-5">
            <div className="mb-3 flex items-center gap-2">
              <Lock className="h-4 w-4 text-[#6E645D]" aria-hidden="true" />
              <h2 className="text-base font-bold text-[#302521]">
                {t('Institutional Record (Dimmed / Read-Only)', 'السجل المؤسسي (للقراءة فقط)')}
              </h2>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="dimmed-field">
                <label htmlFor="profile-email-dim" className="block text-xs font-semibold text-[#6E645D] mb-1.5">
                  {t('University Email', 'البريد الجامعي')}
                </label>
                <input
                  id="profile-email-dim"
                  type="email"
                  value={profile.email}
                  disabled
                  aria-readonly="true"
                  className="w-full min-h-[44px] rounded-xl border border-[#E8E3D9] px-3.5 py-2 text-sm"
                />
              </div>

              <div className="dimmed-field">
                <label htmlFor="profile-programme-dim" className="block text-xs font-semibold text-[#6E645D] mb-1.5">
                  {role === 'Student'
                    ? t('Programme', 'البرنامج الدراسي')
                    : t('Faculty / Department', 'الكلية والقسم')}
                </label>
                <input
                  id="profile-programme-dim"
                  type="text"
                  value={
                    role === 'Student'
                      ? lang === 'ar'
                        ? profile.programmeAr
                        : profile.programme
                      : lang === 'ar'
                        ? profile.departmentAr
                        : profile.department
                  }
                  disabled
                  aria-readonly="true"
                  className="w-full min-h-[44px] rounded-xl border border-[#E8E3D9] px-3.5 py-2 text-sm"
                />
              </div>

              <div className="dimmed-field">
                <label htmlFor="profile-year-dim" className="block text-xs font-semibold text-[#6E645D] mb-1.5">
                  {role === 'Student'
                    ? t('Academic Year', 'السنة الدراسية')
                    : t('Academic Rank', 'الدرجة العلمية')}
                </label>
                <input
                  id="profile-year-dim"
                  type="text"
                  value={
                    role === 'Student'
                      ? lang === 'ar'
                        ? profile.yearAr
                        : profile.year
                      : lang === 'ar'
                        ? profile.rankAr
                        : profile.rank
                  }
                  disabled
                  aria-readonly="true"
                  className="w-full min-h-[44px] rounded-xl border border-[#E8E3D9] px-3.5 py-2 text-sm"
                />
              </div>

              <div className="dimmed-field">
                <label htmlFor="profile-advisor-dim" className="block text-xs font-semibold text-[#6E645D] mb-1.5">
                  {role === 'Student'
                    ? t('Assigned Academic Advisor', 'المرشد الأكاديمي المعين')
                    : t('Assigned Office Room', 'غرفة المكتب المعتمدة')}
                </label>
                <input
                  id="profile-advisor-dim"
                  type="text"
                  value={
                    role === 'Student'
                      ? lang === 'ar'
                        ? profile.advisorAr
                        : profile.advisor
                      : lang === 'ar'
                        ? profile.officeRoomAr
                        : profile.officeRoom
                  }
                  disabled
                  aria-readonly="true"
                  className="w-full min-h-[44px] rounded-xl border border-[#E8E3D9] px-3.5 py-2 text-sm"
                />
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3 pt-2">
            <span className="text-xs text-[#6E645D]">
              {t('Last synced locally in browser storage.', 'آخر مزامنة محفوظة محليًا على المتصفح.')}
            </span>
            <button
              type="submit"
              className="inline-flex min-h-[44px] items-center gap-2 rounded-xl bg-[#B81104] px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-[#940E03]"
            >
              <Save className="h-4 w-4" aria-hidden="true" />
              <span>{t('Save Profile Changes', 'حفظ تعديلات الملف')}</span>
            </button>
          </div>
        </form>
      </div>
    </section>
  );
}
