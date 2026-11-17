import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { AlertCircle, Languages, Loader2, LogOut, MailCheck } from 'lucide-react';
import { configError, supabase } from '../lib/supabase';
import { createApi } from '../lib/api';

/**
 * The signed-in account: `me` (from GET /me), `api` (calls made as this person) and `signOut`.
 * Only rendered once the API has confirmed the account is linked to a university.
 */
const AccountContext = createContext(null);

export function useAccount() {
  const value = useContext(AccountContext);
  if (!value) throw new Error('useAccount must be used inside <AuthGate>.');
  return value;
}

// The workspace keeps its language choice here; the sign-in screens read it so they match.
const STORAGE_KEY = 'cohort-lms-v6';

function storedLanguage() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}').language === 'ar' ? 'ar' : 'en';
  } catch {
    return 'en';
  }
}

function saveLanguage(lang) {
  try {
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...stored, language: lang }));
  } catch {
    // Storage may be unavailable (private mode); the choice then lasts for this visit only.
  }
}

async function accessToken() {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? '';
}

/**
 * Shows sign-in and sign-up until there is a Supabase session, then loads the account from the API
 * and renders the workspace with it. Accounts the university hasn't linked yet see a short
 * explanation instead of the workspace.
 */
export function AuthGate({ children }) {
  const [lang, setLang] = useState(storedLanguage);
  const t = useCallback((en, ar) => (lang === 'ar' && ar ? ar : en), [lang]);
  const toggleLanguage = useCallback(() => {
    setLang((prev) => {
      const next = prev === 'ar' ? 'en' : 'ar';
      saveLanguage(next);
      return next;
    });
  }, []);
  const [session, setSession] = useState(undefined); // undefined while the stored session is read
  const [notice, setNotice] = useState(null);

  // After signing out, pick up any language change made inside the workspace.
  useEffect(() => {
    if (session === null) setLang(storedLanguage());
  }, [session]);

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang, session]);

  useEffect(() => {
    if (!supabase) return undefined;
    let active = true;
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      if (active) setSession(next ?? null);
    });
    supabase.auth.getSession().then(
      ({ data: stored }) => active && setSession(stored.session ?? null),
      () => active && setSession(null)
    );
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, []);

  const sessionEnded = useCallback(() => {
    setNotice(t('Your session has ended. Please sign in again.', 'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.'));
    supabase.auth.signOut();
  }, [t]);

  const chrome = { lang, t, toggleLanguage };

  if (configError) {
    return (
      <AuthLayout {...chrome}>
        <Alert>{configError}</Alert>
      </AuthLayout>
    );
  }
  if (session === undefined) return <FullPageLoader t={t} />;
  if (!session) return <AuthScreen {...chrome} notice={notice} clearNotice={() => setNotice(null)} />;
  return (
    <SignedIn key={session.user.id} {...chrome} email={session.user.email} onSessionEnded={sessionEnded}>
      {children}
    </SignedIn>
  );
}

function SignedIn({ email, onSessionEnded, children, ...chrome }) {
  const { t } = chrome;
  const api = useMemo(() => createApi(accessToken, onSessionEnded), [onSessionEnded]);
  const [state, setState] = useState({ status: 'loading' });
  const signOut = useCallback(() => supabase.auth.signOut(), []);

  const load = useCallback(async () => {
    setState({ status: 'loading' });
    try {
      setState({ status: 'ready', me: await api.me() });
    } catch (error) {
      setState({ status: 'error', error });
    }
  }, [api]);

  useEffect(() => {
    load();
  }, [load]);

  const value = useMemo(
    () => (state.status === 'ready' ? { me: state.me, api, signOut } : null),
    [api, signOut, state]
  );

  if (state.status === 'loading') return <FullPageLoader t={t} />;
  if (state.status === 'error') {
    const notLinked = state.error.status === 403;
    return (
      <AuthLayout {...chrome}>
        <h1 className="text-xl font-extrabold text-[#302521]">
          {notLinked ? t('Almost there', 'اقتربت') : t('Cohort could not load your account', 'تعذّر تحميل حسابك')}
        </h1>
        <p className="mt-2 text-sm text-[#6E645D]">
          {notLinked
            ? t(
                `You're signed in as ${email}, but your university hasn't linked this account yet. Once they do, sign in again to open your workspace.`,
                `لقد سجّلت الدخول باسم ${email}، لكن جامعتك لم تربط هذا الحساب بعد. بعد ربطه، سجّل الدخول مرة أخرى لفتح مساحة عملك.`
              )
            : state.error.message}
        </p>
        <div className="mt-6 flex flex-wrap gap-2">
          {notLinked ? null : (
            <button type="button" onClick={load} className={PRIMARY_BUTTON}>
              {t('Try again', 'حاول مرة أخرى')}
            </button>
          )}
          <button type="button" onClick={signOut} className={SECONDARY_BUTTON}>
            <LogOut className="h-4 w-4" aria-hidden="true" />
            {t('Sign out', 'تسجيل الخروج')}
          </button>
        </div>
      </AuthLayout>
    );
  }
  return <AccountContext.Provider value={value}>{children}</AccountContext.Provider>;
}

const INPUT =
  'mt-1.5 w-full rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2.5 text-sm text-[#302521] placeholder:text-[#A39A92] focus:border-[#B81104] focus:outline-none focus:ring-2 focus:ring-[#B81104]/20';
const PRIMARY_BUTTON =
  'inline-flex min-h-[44px] items-center justify-center gap-2 rounded-xl bg-[#B81104] px-4 py-2.5 text-sm font-bold text-white transition hover:bg-[#940E03] disabled:cursor-not-allowed disabled:opacity-60';
const SECONDARY_BUTTON =
  'inline-flex min-h-[44px] items-center justify-center gap-2 rounded-xl border border-[#E8E3D9] bg-white px-4 py-2.5 text-sm font-semibold text-[#302521] transition hover:border-[#B81104]/50 hover:bg-[#FFF9E4]';

function AuthScreen({ notice, clearNotice, ...chrome }) {
  const { t } = chrome;
  const [mode, setMode] = useState('sign-in');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [sentTo, setSentTo] = useState(null);
  const confirmation = useRef(null);

  useEffect(() => {
    if (sentTo) confirmation.current?.focus();
  }, [sentTo]);

  const switchMode = (next) => {
    setMode(next);
    setError(null);
    clearNotice();
  };

  async function submit(event) {
    event.preventDefault();
    setError(null);
    clearNotice();
    setSubmitting(true);
    try {
      if (mode === 'sign-in') {
        const { error: failure } = await supabase.auth.signInWithPassword({ email, password });
        if (failure) throw failure;
      } else {
        const { data, error: failure } = await supabase.auth.signUp({
          email,
          password,
          options: { data: { full_name: fullName }, emailRedirectTo: `${window.location.origin}/` },
        });
        if (failure) throw failure;
        if (!data.session) setSentTo(email);
      }
    } catch (failure) {
      setError(failure?.message || t('Something went wrong. Please try again.', 'حدث خطأ. حاول مرة أخرى.'));
    } finally {
      setSubmitting(false);
    }
  }

  if (sentTo) {
    return (
      <AuthLayout {...chrome}>
        <MailCheck className="h-8 w-8 text-[#B81104]" aria-hidden="true" />
        <h1 className="mt-3 text-xl font-extrabold text-[#302521]">{t('Check your inbox', 'تحقق من بريدك')}</h1>
        <p ref={confirmation} tabIndex={-1} role="status" className="mt-2 text-sm text-[#6E645D] focus:outline-none">
          {t(
            `We sent a confirmation link to ${sentTo}. After you confirm, your university links the account to your record before you can use Cohort.`,
            `أرسلنا رابط تأكيد إلى ${sentTo}. بعد التأكيد، تربط جامعتك الحساب بسجلك قبل أن تتمكن من استخدام Cohort.`
          )}
        </p>
        <button
          type="button"
          onClick={() => {
            setSentTo(null);
            switchMode('sign-in');
          }}
          className={`${SECONDARY_BUTTON} mt-6`}
        >
          {t('Back to sign in', 'العودة لتسجيل الدخول')}
        </button>
      </AuthLayout>
    );
  }

  const signingUp = mode === 'sign-up';
  return (
    <AuthLayout {...chrome}>
      <h1 className="text-xl font-extrabold text-[#302521]">
        {signingUp ? t('Create your Cohort account', 'أنشئ حسابك في Cohort') : t('Sign in to Cohort', 'تسجيل الدخول إلى Cohort')}
      </h1>
      <p className="mt-1 text-sm text-[#6E645D]">
        {signingUp
          ? t('Use your university email.', 'استخدم بريدك الجامعي.')
          : t('Your courses, timetable and grades in one place.', 'مقرراتك وجدولك ودرجاتك في مكان واحد.')}
      </p>

      {notice ? <Alert tone="info">{notice}</Alert> : null}
      {error ? <Alert>{error}</Alert> : null}

      <form onSubmit={submit} className="mt-5 space-y-4">
        {signingUp ? (
          <div>
            <label htmlFor="auth-full-name" className="text-xs font-bold text-[#302521]">
              {t('Full name', 'الاسم الكامل')}
            </label>
            <input
              id="auth-full-name"
              type="text"
              autoComplete="name"
              required
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className={INPUT}
            />
          </div>
        ) : null}
        <div>
          <label htmlFor="auth-email" className="text-xs font-bold text-[#302521]">
            {t('Email', 'البريد الإلكتروني')}
          </label>
          <input
            id="auth-email"
            type="email"
            autoComplete="email"
            required
            dir="ltr"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={INPUT}
          />
        </div>
        <div>
          <label htmlFor="auth-password" className="text-xs font-bold text-[#302521]">
            {t('Password', 'كلمة المرور')}
          </label>
          <input
            id="auth-password"
            type="password"
            autoComplete={signingUp ? 'new-password' : 'current-password'}
            required
            minLength={signingUp ? 8 : undefined}
            dir="ltr"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={INPUT}
          />
          {signingUp ? (
            <p className="mt-1 text-[11px] text-[#6E645D]">{t('At least 8 characters.', '٨ أحرف على الأقل.')}</p>
          ) : null}
        </div>
        <button type="submit" disabled={submitting} className={`${PRIMARY_BUTTON} w-full`}>
          {submitting ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : null}
          {signingUp ? t('Create account', 'إنشاء حساب') : t('Sign in', 'تسجيل الدخول')}
        </button>
      </form>

      <p className="mt-5 text-center text-sm text-[#6E645D]">
        {signingUp ? t('Already have an account?', 'لديك حساب بالفعل؟') : t('New to Cohort?', 'جديد على Cohort؟')}{' '}
        <button
          type="button"
          onClick={() => switchMode(signingUp ? 'sign-in' : 'sign-up')}
          className="font-bold text-[#B81104] underline-offset-2 hover:underline"
        >
          {signingUp ? t('Sign in', 'تسجيل الدخول') : t('Create an account', 'أنشئ حسابًا')}
        </button>
      </p>
    </AuthLayout>
  );
}

function Alert({ tone = 'error', children }) {
  const styles =
    tone === 'info'
      ? 'border-[#E9DBA9] bg-[#FFF9E4] text-[#302521]'
      : 'border-[#C93636]/30 bg-[#FFE9E5] text-[#8A1F1F]';
  return (
    <div role={tone === 'info' ? 'status' : 'alert'} className={`mt-4 flex items-start gap-2 rounded-xl border px-3 py-2.5 text-sm ${styles}`}>
      <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
      <span>{children}</span>
    </div>
  );
}

function AuthLayout({ lang, t, toggleLanguage, children }) {
  return (
    <div className="min-h-screen bg-[#FAF7F2] text-[#1A1715] antialiased">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-4 sm:px-6">
        <span className="flex items-center gap-2.5">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-[#B81104] text-lg font-extrabold text-[#FFFACD] shadow-sm">
            C
          </span>
          <span className="text-xl font-extrabold tracking-tight text-[#302521]">
            Co<span className="text-[#B81104]">hort</span>
          </span>
        </span>
        <button
          type="button"
          onClick={toggleLanguage}
          className="inline-flex min-h-[40px] items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-semibold text-[#302521] transition hover:border-[#B81104]/50 hover:bg-[#FFF9E4]"
          aria-label={t('Switch language to Arabic', 'تبديل اللغة إلى الإنجليزية')}
        >
          <Languages className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
          <span>{lang === 'ar' ? 'English' : 'العربية'}</span>
        </button>
      </div>
      <main className="mx-auto max-w-md px-4 pb-16 pt-6 sm:pt-12">
        <div className="rounded-3xl border border-[#E8E3D9] bg-white p-6 shadow-sm sm:p-8">{children}</div>
      </main>
    </div>
  );
}

function FullPageLoader({ t }) {
  return (
    <div className="grid min-h-screen place-items-center bg-[#FAF7F2]" role="status" aria-live="polite">
      <span className="flex items-center gap-2 text-sm font-semibold text-[#6E645D]">
        <Loader2 className="h-5 w-5 animate-spin text-[#B81104]" aria-hidden="true" />
        {t('Loading Cohort…', 'جارٍ تحميل Cohort…')}
      </span>
    </div>
  );
}
