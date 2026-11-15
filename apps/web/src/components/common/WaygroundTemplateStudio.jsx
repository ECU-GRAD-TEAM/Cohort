import React, { useEffect, useMemo, useState } from 'react';
import {
  AlertCircle,
  Bold,
  Check,
  CheckCircle2,
  ClipboardCheck,
  FilePlus2,
  GitCompareArrows,
  Italic,
  LayoutList,
  List,
  ListOrdered,
  Mic,
  PenLine,
  Play,
  Plus,
  RotateCcw,
  Send,
  Sparkles,
  ToggleLeft,
  ToggleRight,
  Trash2,
  Type,
  Underline,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { validateRecord } from '../../utils/validation';

export const QUESTION_TYPES = [
  {
    type: 'MCQ',
    labelEn: 'Multiple choice',
    labelAr: 'اختيار من متعدد',
    groupEn: 'Basic',
    badgeEn: 'Auto-graded · Single or Multi-select',
    badgeAr: 'تصحيح تلقائي · اختيار فردي أو متعدد',
    previewEn: 'Question prompt on top with 2–6 option cards and single or multi-select answer keys.',
    previewAr: 'سؤال في الأعلى مع بطاقات إجابة وخيار تحديد إجابة واحدة أو أكثر.',
    Icon: CheckCircle2,
  },
  {
    type: 'True/False',
    labelEn: 'True or false',
    labelAr: 'صح أو خطأ',
    groupEn: 'Basic',
    badgeEn: 'Auto-graded · Rapid check',
    badgeAr: 'تصحيح تلقائي · تحقق سريع',
    previewEn: 'Two bold True / False response cards for fast concept verification.',
    previewAr: 'بطاقتان كبيرتان (صح / خطأ) للتحقق السريع من المفاهيم.',
    Icon: ToggleRight,
  },
  {
    type: 'Fill in the blanks',
    labelEn: 'Fill in the blanks',
    labelAr: 'أكمل الفراغ',
    groupEn: 'Basic',
    badgeEn: 'Auto-graded · Exact / Alias match',
    badgeAr: 'تصحيح تلقائي · مطابقة نصية',
    previewEn: 'Use ___ in your question stem; students type into inline blanks checked automatically.',
    previewAr: 'استخدم ___ في السؤال ليقوم الطالب بملء الفراغات ويتم التصحيح تلقائيًا.',
    Icon: PenLine,
  },
  {
    type: 'Written',
    labelEn: 'Open ended',
    labelAr: 'سؤال مقالي / مفتوح',
    groupEn: 'Basic',
    badgeEn: '3000 char limit · TA Rubric & Review',
    badgeAr: 'حد ٣٠٠٠ حرف · معيار تصحيح ومراجعة',
    previewEn: 'Split canvas with question on the left and a 3000-character student response box on the right.',
    previewAr: 'تصميم منقسم: السؤال على اليسار ومنطقة إجابة الطالب (٣٠٠٠ حرف) على اليمين.',
    Icon: Type,
  },
  {
    type: 'Match',
    labelEn: 'Match pairs',
    labelAr: 'توصيل الأزواج',
    groupEn: 'Basic',
    badgeEn: 'Auto-graded · Side-by-side pairing',
    badgeAr: 'تصحيح تلقائي · مطابقة أزواج',
    previewEn: 'Left concepts matched against target definitions with proportional auto-scoring.',
    previewAr: 'ربط المفاهيم المقابلة مع احتساب الدرجة النسبية تلقائيًا.',
    Icon: GitCompareArrows,
  },
];

// Cohort warm parchment option card surfaces (high contrast with dark espresso #1A1715 text)
const CARD_PALETTES = [
  'bg-[#FFF5F3] border-[#E8C5BE]',
  'bg-[#FFFDF0] border-[#E9DBA9]',
  'bg-[#FAF5EB] border-[#DFD3C3]',
  'bg-[#FFF8E7] border-[#E8D0A7]',
  'bg-[#F7F3EA] border-[#D6CFC1]',
  'bg-[#FFF0ED] border-[#E6B8B3]',
];

function summarizeTemplateTypes(questions = []) {
  const types = Array.from(new Set((questions || []).map((q) => q.type)));
  if (!types.length) return 'Custom Template';
  return types.join(' + ');
}

function normalizeBlankText(val) {
  return String(val || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function isBlankCorrect(expectedRaw, userRaw) {
  const userNorm = normalizeBlankText(userRaw);
  if (!userNorm) return false;
  const acceptedVariants = String(expectedRaw || '')
    .split('|')
    .map(normalizeBlankText)
    .filter(Boolean);
  return acceptedVariants.includes(userNorm);
}

function extractBlankCount(prompt = '') {
  const matches = String(prompt).match(/_{3,}/g);
  return Math.max(1, matches ? matches.length : 1);
}

function getMcqCorrectIndices(q) {
  if (Array.isArray(q.answers) && q.answers.length > 0) {
    return q.answers.map(Number);
  }
  if (q.answer !== undefined && q.answer !== null) {
    return [Number(q.answer)];
  }
  return [];
}

function renderTemplatePromptWithBlanks(prompt, userBlanks = {}, onChangeBlank, qResult, t) {
  const text = String(prompt || '');
  const parts = text.split(/_{3,}/g);
  if (parts.length <= 1) {
    return (
      <div className="space-y-2">
        <p className="text-sm font-bold text-[#1A1715]">{text}</p>
        <input
          type="text"
          value={userBlanks[0] || ''}
          onChange={(e) => onChangeBlank(0, e.target.value)}
          placeholder={t('Type your fill-in-the-blank answer...', 'اكتب الكلمة المفقودة هنا...')}
          aria-label={t('Blank answer', 'إجابة الفراغ')}
          className="w-full sm:w-80 rounded-xl border-2 border-[#D6CFC1] bg-white px-3.5 py-2 text-sm font-semibold text-[#1A1715] focus:border-[#B81104] focus:outline-none"
        />
      </div>
    );
  }

  return (
    <div className="text-sm sm:text-base font-bold text-[#1A1715] leading-loose flex flex-wrap items-center gap-1.5">
      {parts.map((part, idx) => (
        <React.Fragment key={idx}>
          <span>{part}</span>
          {idx < parts.length - 1 ? (
            <input
              type="text"
              value={userBlanks[idx] || ''}
              onChange={(e) => onChangeBlank(idx, e.target.value)}
              placeholder={t(`Blank #${idx + 1}`, `فراغ ${idx + 1}`)}
              aria-label={t(`Fill in blank ${idx + 1}`, `أكمل الفراغ ${idx + 1}`)}
              className={`inline-block min-w-[130px] max-w-[200px] rounded-lg border-2 px-2.5 py-1 text-xs sm:text-sm font-extrabold tabular-nums focus:outline-none ${
                qResult
                  ? qResult.blankMatches?.[idx]
                    ? 'border-[#16845B] bg-[#E8F5EC] text-[#145C40]'
                    : 'border-[#C93636] bg-[#FFE9E5] text-[#9E1C0E]'
                  : 'border-[#B81104]/45 bg-[#FFFACD]/60 text-[#1A1715] focus:border-[#B81104]'
              }`}
            />
          ) : null}
        </React.Fragment>
      ))}
    </div>
  );
}

/**
 * Shared Interactive Assessment & Quiz Builder for Teaching Assistants & Academic Staff.
 * Supports authoring both Course Assignments and Quizzes/Exams across 5 formats.
 */
export function WaygroundBuilder({
  defaultTargetType = 'assignment',
  allowTargetSwitch = true,
  fixedCourseId = '',
  onSaved,
}) {
  const { lang, t, data, setData, showToast } = useCohort();

  const [targetType, setTargetType] = useState(defaultTargetType); // 'assignment' | 'quiz'
  const [selectedQuestionType, setSelectedQuestionType] = useState('MCQ');
  const [hoveredType, setHoveredType] = useState(null);

  const courseOptions = data.courses || [];
  const [draftCourse, setDraftCourse] = useState(fixedCourseId || courseOptions[0]?.id || 'CS201');

  useEffect(() => {
    if (fixedCourseId) setDraftCourse(fixedCourseId);
  }, [fixedCourseId]);

  const targetItems = useMemo(() => {
    const raw = targetType === 'assignment' ? data.assignments : data.quizzes;
    return fixedCourseId ? raw.filter((item) => item.course === fixedCourseId) : raw;
  }, [data.assignments, data.quizzes, fixedCourseId, targetType]);

  const [targetItemId, setTargetItemId] = useState('new');

  // New assignment/quiz metadata
  const [newTitle, setNewTitle] = useState('');
  const [newDueOrDate, setNewDueOrDate] = useState(
    defaultTargetType === 'assignment' ? '2026-11-26 23:59' : '2026-11-25'
  );
  const [newDuration, setNewDuration] = useState(20);
  const [newInstructions, setNewInstructions] = useState('');
  const [queuedQuestions, setQueuedQuestions] = useState([]);

  // Current Slide Canvas state
  const [draftPrompt, setDraftPrompt] = useState('');
  const [draftPoints, setDraftPoints] = useState(5);

  // MCQ / Multi-select canvas state
  const [mcqOptions, setMcqOptions] = useState(['', '', '', '']);
  const [mcqMultiCorrect, setMcqMultiCorrect] = useState(false);
  const [mcqCorrectIndices, setMcqCorrectIndices] = useState([0]);
  const [mcqVerticalLayout, setMcqVerticalLayout] = useState(false);

  // True/False canvas state
  const [tfAnswer, setTfAnswer] = useState(0);

  // Open ended (Written) canvas state
  const [writtenRubric, setWrittenRubric] = useState(
    'Award full marks for clear explanation, complexity or schema justification, and accurate terminology.'
  );
  const [writtenLimit, setWrittenLimit] = useState(3000);

  // Fill in the blanks canvas state
  const [blankAnswers, setBlankAnswers] = useState(['']);

  // Match canvas state
  const [matchPairs, setMatchPairs] = useState([
    { left: 'Balanced BST Lookup', right: 'O(log n)' },
    { left: 'Hash Table Average', right: 'O(1)' },
  ]);

  const [builderError, setBuilderError] = useState('');

  // Keep blank answer inputs synchronized with ___ count in prompt
  const detectedBlanks = useMemo(() => extractBlankCount(draftPrompt), [draftPrompt]);
  useEffect(() => {
    setBlankAnswers((prev) => {
      if (prev.length === detectedBlanks) return prev;
      return Array.from({ length: detectedBlanks }, (_, idx) => prev[idx] || '');
    });
  }, [detectedBlanks]);

  const activePreviewMeta =
    QUESTION_TYPES.find((item) => item.type === (hoveredType || selectedQuestionType)) ||
    QUESTION_TYPES[0];

  const handleToggleTargetType = (nextType) => {
    setTargetType(nextType);
    setTargetItemId('new');
    setNewDueOrDate(nextType === 'assignment' ? '2026-11-26 23:59' : '2026-11-25');
    setBuilderError('');
  };

  const applyPromptSnippet = (snippet) => {
    setDraftPrompt((prev) => (prev ? `${prev}${snippet}` : snippet.trimStart()));
  };

  const handleToggleMcqCorrect = (idx) => {
    if (mcqMultiCorrect) {
      setMcqCorrectIndices((prev) => {
        if (prev.includes(idx)) {
          return prev.length > 1 ? prev.filter((item) => item !== idx) : prev;
        }
        return [...prev, idx].sort((a, b) => a - b);
      });
    } else {
      setMcqCorrectIndices([idx]);
    }
  };

  const handleToggleMultiMode = () => {
    setMcqMultiCorrect((prev) => {
      const next = !prev;
      if (!next && mcqCorrectIndices.length > 1) {
        setMcqCorrectIndices([mcqCorrectIndices[0]]);
      }
      return next;
    });
  };

  const handleAddMcqOption = () => {
    if (mcqOptions.length >= 6) return;
    setMcqOptions((prev) => [...prev, '']);
  };

  const handleDeleteMcqOption = (idx) => {
    if (mcqOptions.length <= 2) return;
    const nextOpts = mcqOptions.filter((_, oIdx) => oIdx !== idx);
    const remapped = mcqCorrectIndices
      .filter((cIdx) => cIdx !== idx)
      .map((cIdx) => (cIdx > idx ? cIdx - 1 : cIdx));
    setMcqOptions(nextOpts);
    setMcqCorrectIndices(remapped.length ? remapped : [0]);
  };

  const buildCurrentQuestion = () => {
    const cleanPrompt = draftPrompt.trim();
    if (!cleanPrompt) {
      return { error: t('Type a question prompt in the slide canvas first.', 'اكتب نص السؤال في لوحة التصميم أولاً.') };
    }

    const qId = `q-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    const points = Math.max(1, Number(draftPoints) || 5);

    if (selectedQuestionType === 'MCQ') {
      const indexedOptions = mcqOptions
        .map((txt, origIdx) => ({ txt: txt.trim(), origIdx }))
        .filter((entry) => Boolean(entry.txt));

      if (indexedOptions.length < 2) {
        return {
          error: t(
            'Fill in at least 2 answer option cards before saving an MCQ question.',
            'اكتب خيارين على الأقل في بطاقات الإجابة لسؤال الاختيار من متعدد.'
          ),
        };
      }

      const mappedCorrect = mcqCorrectIndices
        .map((origIdx) => indexedOptions.findIndex((item) => item.origIdx === origIdx))
        .filter((mappedIdx) => mappedIdx >= 0);

      const finalAnswers = mappedCorrect.length ? mappedCorrect : [0];
      const cleanedTexts = indexedOptions.map((item) => item.txt);

      const err = validateRecord('questions', {
        type: 'Multiple choice',
        options: cleanedTexts.join('\n'),
        answer: String(finalAnswers[0]),
      });
      if (err) return { error: err };

      return {
        question: {
          id: qId,
          type: 'MCQ',
          prompt: cleanPrompt,
          options: cleanedTexts,
          answer: finalAnswers[0],
          answers: finalAnswers,
          multipleCorrect: mcqMultiCorrect,
          layout: mcqVerticalLayout ? 'vertical' : 'horizontal',
          points,
        },
      };
    }

    if (selectedQuestionType === 'True/False') {
      const err = validateRecord('questions', {
        type: 'True / false',
        options: 'True\nFalse',
        answer: String(tfAnswer),
      });
      if (err) return { error: err };

      return {
        question: {
          id: qId,
          type: 'True/False',
          prompt: cleanPrompt,
          options: ['True', 'False'],
          answer: Number(tfAnswer),
          points,
        },
      };
    }

    if (selectedQuestionType === 'Fill in the blanks') {
      const cleanedBlanks = blankAnswers.map((b) => b.trim()).filter(Boolean);
      if (!cleanedBlanks.length) {
        return {
          error: t(
            'Enter the accepted fill-in-the-blank answer on the right panel.',
            'أدخل الإجابة المقبولة للفراغ في اللوحة اليمنى.'
          ),
        };
      }
      return {
        question: {
          id: qId,
          type: 'Fill in the blanks',
          prompt: cleanPrompt.includes('___') ? cleanPrompt : `${cleanPrompt} ___`,
          blanks: blankAnswers.map((b) => b.trim() || cleanedBlanks[0]),
          points,
        },
      };
    }

    if (selectedQuestionType === 'Match') {
      const cleanedPairs = matchPairs
        .map((p) => ({ left: p.left.trim(), right: p.right.trim() }))
        .filter((p) => p.left && p.right);

      if (cleanedPairs.length < 2) {
        return {
          error: t('Add at least 2 complete matching pairs (left & right).', 'أضف زوجي توصيل كاملين على الأقل.'),
        };
      }

      const err = validateRecord('questions', {
        type: 'Matching',
        options: cleanedPairs.map((p) => `${p.left} = ${p.right}`).join('\n'),
      });
      if (err) return { error: err };

      return {
        question: {
          id: qId,
          type: 'Match',
          prompt: cleanPrompt,
          pairs: cleanedPairs,
          points,
        },
      };
    }

    // Written (Open ended)
    return {
      question: {
        id: qId,
        type: 'Written',
        prompt: cleanPrompt,
        rubric: writtenRubric.trim(),
        maxLength: Number(writtenLimit) || 3000,
        points,
      },
    };
  };

  const resetCanvasForNextQuestion = () => {
    setDraftPrompt('');
    setMcqOptions(['', '', '', '']);
    setMcqCorrectIndices([0]);
    setBlankAnswers(['']);
    setBuilderError('');
  };

  const handleQueueQuestion = () => {
    const built = buildCurrentQuestion();
    if (built.error) {
      setBuilderError(built.error);
      return;
    }

    if (targetItemId !== 'new') {
      // Append immediately to the existing assignment or quiz
      commitQuestionsToExisting(targetItemId, [built.question]);
      resetCanvasForNextQuestion();
      return;
    }

    setQueuedQuestions((prev) => [...prev, built.question]);
    resetCanvasForNextQuestion();
    showToast(
      t(
        `Added Question #${queuedQuestions.length + 1} (${built.question.type}) to draft. Pick the next type or publish!`,
        `تمت إضافة السؤال رقم ${queuedQuestions.length + 1} (${built.question.type}) للمسودة.`
      )
    );
  };

  const commitQuestionsToExisting = (itemId, newQuestions) => {
    if (targetType === 'assignment') {
      setData((prev) => ({
        ...prev,
        assignments: prev.assignments.map((asg) => {
          if (asg.id !== itemId) return asg;
          const combined = [...(asg.questions || []), ...newQuestions];
          return {
            ...asg,
            questions: combined,
            templateType: summarizeTemplateTypes(combined),
          };
        }),
      }));
    } else {
      setData((prev) => ({
        ...prev,
        quizzes: prev.quizzes.map((qz) =>
          qz.id === itemId ? { ...qz, questions: [...(qz.questions || []), ...newQuestions] } : qz
        ),
      }));
    }

    showToast(
      t(
        `Saved ${newQuestions.length} question(s) to existing ${targetType}.`,
        `تم حفظ ${newQuestions.length} سؤال في ${targetType === 'assignment' ? 'التكليف' : 'الاختبار'}.`
      )
    );
    if (onSaved) onSaved({ id: itemId, targetType });
  };

  const handleSaveAssessment = (e) => {
    e.preventDefault();

    let questionsToSave = [...queuedQuestions];
    if (draftPrompt.trim() || targetItemId !== 'new' || questionsToSave.length === 0) {
      const built = buildCurrentQuestion();
      if (built.error) {
        if (targetItemId === 'new' && questionsToSave.length > 0 && !draftPrompt.trim()) {
          // Allow publishing if they already queued questions and left the slide empty
        } else {
          setBuilderError(built.error);
          return;
        }
      } else {
        questionsToSave.push(built.question);
      }
    }

    if (targetItemId !== 'new') {
      commitQuestionsToExisting(targetItemId, questionsToSave);
      setQueuedQuestions([]);
      resetCanvasForNextQuestion();
      return;
    }

    const cleanTitle = newTitle.trim();
    if (!cleanTitle) {
      setBuilderError(
        t(
          `Enter a title for the new ${targetType === 'assignment' ? 'assignment' : 'quiz'}.`,
          'يرجى إدخال عنوان التقييم الجديد.'
        )
      );
      return;
    }

    const targetCourse = fixedCourseId || draftCourse;
    if (targetType === 'assignment') {
      const newAsg = {
        id: `asg-${Date.now()}`,
        course: targetCourse,
        title: cleanTitle,
        titleAr: cleanTitle,
        due: newDueOrDate.trim() || '2026-11-26 23:59',
        templateType: summarizeTemplateTypes(questionsToSave),
        submitted: false,
        status: 'Upcoming',
        instructions:
          newInstructions.trim() ||
          'Complete all interactive questions and submit any written explanations for review.',
        questions: questionsToSave,
      };
      setData((prev) => ({
        ...prev,
        assignments: [newAsg, ...prev.assignments],
      }));
      showToast(
        t(
          `Published assignment "${cleanTitle}" (${questionsToSave.length} Qs · ${newAsg.templateType}).`,
          `تم نشر التكليف "${cleanTitle}" (${questionsToSave.length} أسئلة).`
        )
      );
      setNewTitle('');
      setNewInstructions('');
      setQueuedQuestions([]);
      resetCanvasForNextQuestion();
      if (onSaved) onSaved({ id: newAsg.id, targetType: 'assignment' });
    } else {
      const newQuiz = {
        id: `qz-${Date.now()}`,
        course: targetCourse,
        title: cleanTitle,
        titleAr: cleanTitle,
        kind: 'Quiz',
        duration: Math.max(5, Number(newDuration) || 20),
        date: newDueOrDate.trim() || '2026-11-25',
        status: 'Published',
        questions: questionsToSave,
      };
      setData((prev) => ({
        ...prev,
        quizzes: [newQuiz, ...prev.quizzes],
      }));
      showToast(
        t(
          `Published quiz "${cleanTitle}" (${questionsToSave.length} Qs).`,
          `تم نشر الاختبار "${cleanTitle}" (${questionsToSave.length} أسئلة).`
        )
      );
      setNewTitle('');
      setNewInstructions('');
      setQueuedQuestions([]);
      resetCanvasForNextQuestion();
      if (onSaved) onSaved({ id: newQuiz.id, targetType: 'quiz' });
    }
  };

  return (
    <form
      onSubmit={handleSaveAssessment}
      className="cohort-card rounded-2xl p-4 sm:p-5 space-y-4 border border-[#E5DCCF]"
    >
      {/* Top Studio Header & Assignment/Quiz Switcher */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-3 border-b border-[#EFE7DA] pb-3.5">
        <div>
          <span className="text-[11px] font-bold uppercase tracking-wider text-[#B81104]">
            {t('TA & FACULTY TEMPLATE AUTHOR', 'استوديو قوالب التكليفات والاختبارات للمعيد والمحاضر')}
          </span>
          <h3 className="text-base sm:text-lg font-extrabold text-[#1A1715]">
            {targetType === 'assignment'
              ? t('Interactive Assignment Template Builder', 'بناء تكليف تفاعلي متعدد الأنماط')
              : t('Interactive Quiz Template Builder', 'بناء اختبار تفاعلي متعدد الأنماط')}
          </h3>
        </div>

        {allowTargetSwitch ? (
          <div
            role="group"
            aria-label={t('Target template mode', 'نوع التقييم')}
            className="inline-flex rounded-xl bg-[#F4EFE6] p-1 border border-[#E5DCCF] self-start lg:self-auto"
          >
            <button
              type="button"
              onClick={() => handleToggleTargetType('assignment')}
              className={`rounded-lg px-3 py-1.5 text-xs font-bold transition ${
                targetType === 'assignment'
                  ? 'bg-[#B81104] text-[#FFFACD] shadow-sm'
                  : 'text-[#6E645D] hover:text-[#1A1715]'
              }`}
            >
              {t('Assignment Template', 'تكليف (Assignment)')}
            </button>
            <button
              type="button"
              onClick={() => handleToggleTargetType('quiz')}
              className={`rounded-lg px-3 py-1.5 text-xs font-bold transition ${
                targetType === 'quiz'
                  ? 'bg-[#B81104] text-[#FFFACD] shadow-sm'
                  : 'text-[#6E645D] hover:text-[#1A1715]'
              }`}
            >
              {t('Quiz / Exam Template', 'اختبار (Quiz)')}
            </button>
          </div>
        ) : null}
      </div>

      {/* Target Existing vs Create New Metadata */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
        <div className="md:col-span-5">
          <label htmlFor="wg-target-select" className="block text-[11px] font-bold text-[#6E645D] mb-1">
            {targetType === 'assignment'
              ? t('Target Assignment', 'التكليف المستهدف')
              : t('Target Quiz / Exam', 'الاختبار المستهدف')}
          </label>
          <select
            id="wg-target-select"
            value={targetItemId}
            onChange={(e) => {
              setTargetItemId(e.target.value);
              setQueuedQuestions([]);
              setBuilderError('');
            }}
            className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs font-bold text-[#1A1715]"
          >
            <option value="new">
              {targetType === 'assignment'
                ? t('+ Create New Assignment', '+ إنشاء تكليف جديد')
                : t('+ Create New Quiz', '+ إنشاء اختبار جديد')}
            </option>
            {targetItems.map((item) => (
              <option key={item.id} value={item.id}>
                {item.course} · {lang === 'ar' ? item.titleAr : item.title} ({(item.questions || []).length} Qs)
              </option>
            ))}
          </select>
        </div>

        {targetItemId === 'new' ? (
          <>
            {!fixedCourseId ? (
              <div className="md:col-span-2">
                <label htmlFor="wg-course" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                  {t('Course', 'المقرر')}
                </label>
                <select
                  id="wg-course"
                  value={draftCourse}
                  onChange={(e) => setDraftCourse(e.target.value)}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs font-bold text-[#1A1715]"
                >
                  {courseOptions.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.id}
                    </option>
                  ))}
                </select>
              </div>
            ) : null}

            <div className={fixedCourseId ? 'md:col-span-4' : 'md:col-span-3'}>
              <label htmlFor="wg-title" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {targetType === 'assignment'
                  ? t('New Assignment Title', 'عنوان التكليف')
                  : t('New Quiz Title', 'عنوان الاختبار')}
              </label>
              <input
                id="wg-title"
                type="text"
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                placeholder={
                  targetType === 'assignment'
                    ? t('e.g., Week 8 Tree Balancing Lab', 'مثال: معمل الأسبوع الثامن')
                    : t('e.g., Lecture 6 Concept Check', 'مثال: اختبار المفاهيم')
                }
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#1A1715]"
              />
            </div>

            <div className={fixedCourseId ? 'md:col-span-3' : 'md:col-span-2'}>
              <label htmlFor="wg-due" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {targetType === 'assignment'
                  ? t('Due Date', 'موعد التسليم')
                  : t('Quiz Date', 'تاريخ الاختبار')}
              </label>
              <input
                id="wg-due"
                type="text"
                value={newDueOrDate}
                onChange={(e) => setNewDueOrDate(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs tabular-nums text-[#1A1715]"
              />
            </div>

            {targetType === 'assignment' ? (
              <div className="md:col-span-12">
                <input
                  type="text"
                  value={newInstructions}
                  onChange={(e) => setNewInstructions(e.target.value)}
                  aria-label={t('Assignment instructions', 'تعليمات التكليف')}
                  placeholder={t(
                    'Instructions for students (optional — e.g., Complete all checkpoints and explain worst-case runtime)...',
                    'تعليمات التكليف للطلاب (اختياري)...'
                  )}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#1A1715]"
                />
              </div>
            ) : (
              <div className="md:col-span-12 flex items-center gap-3">
                <label htmlFor="wg-dur" className="text-[11px] font-bold text-[#6E645D]">
                  {t('Duration (min):', 'المدة (بالدقائق):')}
                </label>
                <input
                  id="wg-dur"
                  type="number"
                  min="5"
                  max="180"
                  value={newDuration}
                  onChange={(e) => setNewDuration(e.target.value)}
                  className="w-24 rounded-xl border border-[#D6CFC1] bg-white px-3 py-1.5 text-xs font-bold tabular-nums text-[#1A1715]"
                />
              </div>
            )}
          </>
        ) : (
          <div className="md:col-span-7 flex items-center text-xs text-[#6E645D]">
            {t(
              'Questions authored in the canvas below will append directly to the selected assessment.',
              'الأسئلة المصممة أدناه ستُضاف مباشرة إلى التقييم المحدد.'
            )}
          </div>
        )}
      </div>

      {/* Interactive "Question types · Hover to preview" Bar */}
      <div className="rounded-2xl bg-[#FCFBF6] text-[#1A1715] p-4 space-y-3 border border-[#E5DCCF]">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2.5">
            <span className="text-sm font-extrabold text-[#1A1715]">
              {t('Question types', 'أنواع الأسئلة')}
            </span>
            <span className="inline-flex items-center gap-1 rounded-full bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-0.5 text-[11px] font-bold text-[#960D03]">
              {t('Hover to preview · Select answer category', 'مرر للمعاينة · اختر نمط الإجابة')}
            </span>
          </div>

          <div className="flex items-center gap-2">
            <label htmlFor="wg-points" className="text-[11px] font-bold text-[#6E645D]">
              {t('Points:', 'الدرجة:')}
            </label>
            <input
              id="wg-points"
              type="number"
              min="1"
              max="100"
              value={draftPoints}
              onChange={(e) => setDraftPoints(e.target.value)}
              className="w-16 rounded-lg border border-[#D6CFC1] bg-white px-2 py-1 text-xs font-extrabold text-[#B81104] tabular-nums text-center"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
          {QUESTION_TYPES.map((item) => {
            const active = selectedQuestionType === item.type;
            const ItemIcon = item.Icon;
            return (
              <button
                key={item.type}
                type="button"
                onMouseEnter={() => setHoveredType(item.type)}
                onMouseLeave={() => setHoveredType(null)}
                onFocus={() => setHoveredType(item.type)}
                onBlur={() => setHoveredType(null)}
                onClick={() => {
                  setSelectedQuestionType(item.type);
                  setBuilderError('');
                }}
                className={`flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-start border transition ${
                  active
                    ? 'bg-[#FFFACD] border-[#B81104] text-[#960D03] shadow-sm'
                    : 'bg-white border-[#E5DCCF] text-[#302521] hover:border-[#B81104]/50 hover:bg-[#FAF5EB]'
                }`}
              >
                <span
                  className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${
                    active ? 'bg-[#B81104] text-[#FFFACD]' : 'bg-[#FFF0ED] text-[#B81104]'
                  }`}
                >
                  <ItemIcon className="h-4 w-4" aria-hidden="true" />
                </span>
                <span className="text-xs font-bold leading-tight">
                  {lang === 'ar' ? item.labelAr : item.labelEn}
                </span>
              </button>
            );
          })}
        </div>

        {/* Live Hover / Active Preview Strip */}
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white border border-[#E5DCCF] px-3 py-2 text-[11px]">
          <span className="text-[#6E645D]">
            <strong className="text-[#1A1715]">
              {lang === 'ar' ? activePreviewMeta.labelAr : activePreviewMeta.labelEn}:
            </strong>{' '}
            {lang === 'ar' ? activePreviewMeta.previewAr : activePreviewMeta.previewEn}
          </span>
          <span className="rounded-md bg-[#FFFACD] border border-[#E9DBA9] px-2 py-0.5 text-[10px] font-bold text-[#960D03]">
            {lang === 'ar' ? activePreviewMeta.badgeAr : activePreviewMeta.badgeEn}
          </span>
        </div>
      </div>

      {/* Interactive Cohort Slide Canvas (Adapts per Selected Question Type) */}
      <div className="rounded-2xl bg-[#F7F3EA] p-4 sm:p-5 space-y-4 border border-[#E5DCCF] text-[#1A1715]">
        {selectedQuestionType === 'Written' ? (
          /* Open Ended Split Canvas */
          <div className="space-y-4">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {/* Left Panel: Question Prompt + Mic */}
              <div className="flex flex-col rounded-2xl border-2 border-[#E5DCCF] bg-white p-3.5 min-h-[250px] focus-within:border-[#B81104]">
                <div className="flex items-center justify-between gap-2 pb-2">
                  <span className="inline-flex h-7 w-7 items-center justify-center rounded-lg bg-[#FFF0ED] text-[#B81104]">
                    <Mic className="h-3.5 w-3.5" aria-hidden="true" />
                  </span>
                  <span className="text-[11px] font-bold text-[#B81104]">
                    {t('Open ended · Prompt', 'السؤال المقالي')}
                  </span>
                </div>
                <textarea
                  value={draftPrompt}
                  onChange={(e) => setDraftPrompt(e.target.value)}
                  aria-label={t('Open ended question prompt', 'نص السؤال المقالي')}
                  placeholder={t('Type question here', 'اكتب السؤال هنا')}
                  className="flex-1 w-full resize-none bg-transparent text-center text-base sm:text-lg font-semibold text-[#1A1715] placeholder-[#6E645D] focus:outline-none py-8 px-3"
                />
              </div>

              {/* Right Panel: Formatting Toolbar + Student Response Preview Box ("3000 character limit") */}
              <div className="flex flex-col space-y-2">
                <div className="flex flex-wrap items-center gap-1.5 px-1 text-[#6E645D]">
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' **key term**')}
                    aria-label="Bold format"
                    className="rounded p-1 hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    <Bold className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' *note*')}
                    aria-label="Italic format"
                    className="rounded p-1 hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    <Italic className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' __underlined__')}
                    aria-label="Underline format"
                    className="rounded p-1 hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    <Underline className="h-3.5 w-3.5" />
                  </button>
                  <span className="h-4 w-px bg-[#D6CFC1] mx-0.5" />
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet('\n1. ')}
                    aria-label="Numbered list"
                    className="rounded p-1 hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    <ListOrdered className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet('\n- ')}
                    aria-label="Bullet list"
                    className="rounded p-1 hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    <List className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' O(log n)')}
                    className="rounded px-1.5 py-0.5 text-xs font-bold hover:bg-[#FFFACD] hover:text-[#960D03]"
                  >
                    Ω
                  </button>
                  <div className="ms-auto flex items-center gap-1.5">
                    <label htmlFor="wg-charlimit" className="text-[10px] font-bold text-[#6E645D]">
                      {t('Max chars:', 'الحد:')}
                    </label>
                    <select
                      id="wg-charlimit"
                      value={writtenLimit}
                      onChange={(e) => setWrittenLimit(Number(e.target.value))}
                      className="rounded border border-[#D6CFC1] bg-white px-1.5 py-0.5 text-[11px] font-bold text-[#B81104]"
                    >
                      <option value={500}>500</option>
                      <option value={1500}>1500</option>
                      <option value={3000}>3000</option>
                    </select>
                  </div>
                </div>

                <div className="flex-1 rounded-2xl border-2 border-[#E9DBA9] bg-[#FFFACD]/60 p-5 flex flex-col justify-between min-h-[218px]">
                  <div />
                  <p className="text-center text-base sm:text-lg font-medium text-[#302521]">
                    {t('Students will type their response here', 'سيكتب الطلاب إجاباتهم هنا')}
                  </p>
                  <div className="text-end text-xs font-bold text-[#960D03] tabular-nums">
                    {writtenLimit} {t('character limit', 'حد أقصى للأحرف')}
                  </div>
                </div>
              </div>
            </div>

            <div>
              <label htmlFor="wg-rubric" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('TA Grading Rubric / Model Notes (shown after submission or during review)', 'معيار تصحيح المعيد / ملاحظات الإجابة النموذجية')}
              </label>
              <input
                id="wg-rubric"
                type="text"
                value={writtenRubric}
                onChange={(e) => setWrittenRubric(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#1A1715] placeholder-[#6E645D]"
              />
            </div>
          </div>
        ) : selectedQuestionType === 'Fill in the blanks' ? (
          /* Fill-in-the-blanks Split Canvas */
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="flex flex-col rounded-2xl border-2 border-[#E5DCCF] bg-white p-4 min-h-[220px] space-y-2 focus-within:border-[#B81104]">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="text-[11px] font-bold text-[#6E645D]">
                  {t('Question Stem (use ___ for each blank)', 'نص السؤال (استخدم ___ لموضع الفراغ)')}
                </span>
                <button
                  type="button"
                  onClick={() => applyPromptSnippet(' ___ ')}
                  className="rounded-lg bg-[#B81104] px-2.5 py-1 text-[11px] font-bold text-[#FFFACD] hover:bg-[#960D03]"
                >
                  + {t('Insert Blank (___)', 'إدراج فراغ (___)')}
                </button>
              </div>
              <textarea
                value={draftPrompt}
                onChange={(e) => setDraftPrompt(e.target.value)}
                aria-label={t('Fill in the blanks question prompt', 'نص سؤال أكمل الفراغ')}
                placeholder={t(
                  'Type question here (e.g., Deleting a BST node with two children replaces it with its in-order ___).',
                  'اكتب السؤال هنا واستخدم ___ لمكان الفراغ...'
                )}
                className="flex-1 w-full resize-none bg-transparent text-center text-base font-semibold text-[#1A1715] placeholder-[#6E645D] focus:outline-none py-6 px-2"
              />
            </div>

            <div className="rounded-2xl border-2 border-[#E5DCCF] bg-white p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-extrabold text-[#B81104]">
                  {t('Accepted Blank Answer(s)', 'الإجابات المقبولة للفراغات')}
                </span>
                <span className="text-[11px] text-[#6E645D]">
                  {t('Case-insensitive · Use | for synonyms', 'غير حساس لحالة الأحرف · استخدم | للمرادفات')}
                </span>
              </div>

              <div className="space-y-2">
                {blankAnswers.map((val, idx) => (
                  <div key={idx} className="space-y-1">
                    <label
                      htmlFor={`wg-blank-${idx}`}
                      className="block text-[11px] font-bold text-[#302521]"
                    >
                      {t(`Blank #${idx + 1} Answer Key`, `مفتاح الفراغ #${idx + 1}`)}
                    </label>
                    <input
                      id={`wg-blank-${idx}`}
                      type="text"
                      value={val}
                      onChange={(e) =>
                        setBlankAnswers((prev) =>
                          prev.map((item, bIdx) => (bIdx === idx ? e.target.value : item))
                        )
                      }
                      placeholder={t('e.g., successor | predecessor', 'مثال: successor')}
                      className="w-full rounded-xl border border-[#D6CFC1] bg-[#FCFBF6] px-3 py-2 text-xs font-bold text-[#1A1715] placeholder-[#6E645D]"
                    />
                  </div>
                ))}
              </div>
            </div>
          </div>
        ) : selectedQuestionType === 'Match' ? (
          /* Match Pairs Canvas */
          <div className="space-y-4">
            <div className="rounded-2xl border-2 border-[#E5DCCF] bg-white p-4 focus-within:border-[#B81104]">
              <div className="flex items-center justify-between pb-2">
                <span className="inline-flex h-7 w-7 items-center justify-center rounded-lg bg-[#FFF0ED] text-[#B81104]">
                  <GitCompareArrows className="h-3.5 w-3.5" aria-hidden="true" />
                </span>
                <span className="text-[11px] font-bold text-[#B81104]">
                  {t('Match Pairs Prompt', 'عنوان سؤال التوصيل')}
                </span>
              </div>
              <textarea
                rows={2}
                value={draftPrompt}
                onChange={(e) => setDraftPrompt(e.target.value)}
                placeholder={t('Type question prompt here (e.g., Match each normal form with its rule)', 'اكتب عنوان سؤال التوصيل هنا...')}
                className="w-full resize-none bg-transparent text-center text-base font-semibold text-[#1A1715] placeholder-[#6E645D] focus:outline-none py-2"
              />
            </div>

            <div className="space-y-2">
              {matchPairs.map((pair, idx) => (
                <div key={idx} className="grid grid-cols-1 sm:grid-cols-11 gap-2 items-center">
                  <input
                    type="text"
                    value={pair.left}
                    onChange={(e) =>
                      setMatchPairs((prev) =>
                        prev.map((item, pIdx) => (pIdx === idx ? { ...item, left: e.target.value } : item))
                      )
                    }
                    placeholder={t(`Prompt item ${idx + 1}`, `العنصر ${idx + 1}`)}
                    className="sm:col-span-5 rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/60 px-3 py-2.5 text-xs font-bold text-[#302521] placeholder-[#6E645D]"
                  />
                  <span className="sm:col-span-1 text-center text-xs font-extrabold text-[#B81104]">
                    ⇄
                  </span>
                  <input
                    type="text"
                    value={pair.right}
                    onChange={(e) =>
                      setMatchPairs((prev) =>
                        prev.map((item, pIdx) => (pIdx === idx ? { ...item, right: e.target.value } : item))
                      )
                    }
                    placeholder={t(`Matching target ${idx + 1}`, `الإجابة المطابقة ${idx + 1}`)}
                    className="sm:col-span-4 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2.5 text-xs font-bold text-[#1A1715] placeholder-[#6E645D]"
                  />
                  <button
                    type="button"
                    disabled={matchPairs.length <= 2}
                    onClick={() => setMatchPairs((prev) => prev.filter((_, pIdx) => pIdx !== idx))}
                    aria-label={t(`Remove pair ${idx + 1}`, `حذف الزوج ${idx + 1}`)}
                    className="sm:col-span-1 inline-flex items-center justify-center rounded-xl border border-[#E5DCCF] bg-white p-2 text-[#B81104] hover:bg-[#FFE9E5] disabled:opacity-30"
                  >
                    <Trash2 className="h-4 w-4" aria-hidden="true" />
                  </button>
                </div>
              ))}
              {matchPairs.length < 6 ? (
                <button
                  type="button"
                  onClick={() => setMatchPairs((prev) => [...prev, { left: '', right: '' }])}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-3 py-1.5 text-xs font-bold text-[#960D03] hover:bg-[#FFF2B5]"
                >
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  {t('Add Matching Pair', 'إضافة زوج توصيل')}
                </button>
              ) : null}
            </div>
          </div>
        ) : (
          /* MCQ & True/False Option Cards Canvas */
          <div className="space-y-4">
            {/* Top Question Stem Container */}
            <div className="rounded-2xl border-2 border-[#E5DCCF] bg-white p-4 min-h-[145px] flex flex-col justify-between focus-within:border-[#B81104]">
              <div className="flex items-center justify-between gap-2">
                <span className="inline-flex h-7 w-7 items-center justify-center rounded-lg bg-[#FFF0ED] text-[#B81104]">
                  <Mic className="h-3.5 w-3.5" aria-hidden="true" />
                </span>
                <div className="flex items-center gap-1.5 text-[#6E645D]">
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' **term**')}
                    className="rounded px-1.5 py-0.5 text-xs font-bold hover:bg-[#FFFACD] hover:text-[#960D03]"
                    title="Insert Bold"
                  >
                    B
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' *detail*')}
                    className="rounded px-1.5 py-0.5 text-xs italic hover:bg-[#FFFACD] hover:text-[#960D03]"
                    title="Insert Italic"
                  >
                    I
                  </button>
                  <button
                    type="button"
                    onClick={() => applyPromptSnippet(' O(log n)')}
                    className="rounded px-1.5 py-0.5 text-xs font-bold hover:bg-[#FFFACD] hover:text-[#960D03]"
                    title="Insert Symbol"
                  >
                    Ω
                  </button>
                </div>
              </div>

              <textarea
                rows={3}
                value={draftPrompt}
                onChange={(e) => setDraftPrompt(e.target.value)}
                aria-label={t('Question prompt', 'نص السؤال')}
                placeholder={t('Type question here', 'اكتب السؤال هنا')}
                className="w-full resize-none bg-transparent text-center text-base sm:text-lg font-semibold text-[#1A1715] placeholder-[#6E645D] focus:outline-none py-3 px-2"
              />
              <div />
            </div>

            {selectedQuestionType === 'True/False' ? (
              /* Two large True / False cards */
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {['True', 'False'].map((label, idx) => {
                  const isCorrect = Number(tfAnswer) === idx;
                  return (
                    <button
                      key={label}
                      type="button"
                      onClick={() => setTfAnswer(idx)}
                      className={`relative rounded-2xl border-2 p-6 min-h-[120px] flex flex-col items-center justify-center transition ${
                        isCorrect
                          ? 'bg-[#FFFACD] border-[#B81104] ring-2 ring-[#B81104] shadow-md'
                          : 'bg-white border-[#E5DCCF] hover:border-[#B81104]/50'
                      }`}
                    >
                      <span
                        className={`absolute top-3 end-3 flex h-7 w-7 items-center justify-center rounded-full border ${
                          isCorrect
                            ? 'border-[#16845B] bg-[#16845B] text-white'
                            : 'border-[#D6CFC1] bg-[#FCFBF6] text-[#6E645D]'
                        }`}
                      >
                        <Check className="h-4 w-4" aria-hidden="true" />
                      </span>
                      <span className="text-lg font-extrabold text-[#1A1715]">{label}</span>
                      <span
                        className={`text-[11px] font-bold mt-1 ${
                          isCorrect ? 'text-[#16845B]' : 'text-[#6E645D]'
                        }`}
                      >
                        {isCorrect
                          ? t('Marked as correct answer', 'محدد كإجابة صحيحة')
                          : t('Click to mark correct', 'اضغط لتحديده كصحيح')}
                      </span>
                    </button>
                  );
                })}
              </div>
            ) : (
              /* 4-card (or vertical) MCQ Answer Cards + Bottom Control Bar */
              <>
                <div className="flex flex-col sm:flex-row items-stretch gap-2.5">
                  <div
                    className={`flex-1 grid gap-2.5 ${
                      mcqVerticalLayout
                        ? 'grid-cols-1'
                        : mcqOptions.length <= 2
                          ? 'grid-cols-1 sm:grid-cols-2'
                          : mcqOptions.length === 3
                            ? 'grid-cols-1 sm:grid-cols-3'
                            : 'grid-cols-1 sm:grid-cols-2 xl:grid-cols-4'
                    }`}
                  >
                    {mcqOptions.map((opt, idx) => {
                      const isChecked = mcqCorrectIndices.includes(idx);
                      const palette = CARD_PALETTES[idx % CARD_PALETTES.length];
                      return (
                        <div
                          key={idx}
                          className={`relative rounded-2xl border-2 p-3 flex flex-col justify-between transition ${
                            isChecked
                              ? 'bg-[#FFFACD] border-[#B81104] ring-2 ring-[#B81104] shadow-md'
                              : palette
                          } ${mcqVerticalLayout ? 'min-h-[82px]' : 'min-h-[168px]'}`}
                        >
                          <div className="flex items-center justify-between gap-2">
                            <button
                              type="button"
                              disabled={mcqOptions.length <= 2}
                              onClick={() => handleDeleteMcqOption(idx)}
                              aria-label={t(`Delete option ${idx + 1}`, `حذف الخيار ${idx + 1}`)}
                              className="flex h-7 w-7 items-center justify-center rounded-lg bg-white/90 border border-[#E5DCCF] text-[#960D03] hover:bg-[#FFE9E5] disabled:opacity-30"
                            >
                              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                            </button>

                            <button
                              type="button"
                              onClick={() => handleToggleMcqCorrect(idx)}
                              aria-pressed={isChecked}
                              aria-label={t(`Mark option ${idx + 1} as correct`, `تحديد الخيار ${idx + 1} كصحيح`)}
                              className={`flex h-7 w-7 items-center justify-center rounded-full border transition ${
                                isChecked
                                  ? 'border-[#16845B] bg-[#16845B] text-white'
                                  : 'border-[#D6CFC1] bg-white text-[#6E645D] hover:border-[#B81104] hover:text-[#B81104]'
                              }`}
                            >
                              <Check className="h-3.5 w-3.5" aria-hidden="true" />
                            </button>
                          </div>

                          <textarea
                            rows={mcqVerticalLayout ? 1 : 3}
                            value={opt}
                            onChange={(e) =>
                              setMcqOptions((prev) =>
                                prev.map((item, oIdx) => (oIdx === idx ? e.target.value : item))
                              )
                            }
                            aria-label={t(`Answer option ${idx + 1}`, `نص الخيار ${idx + 1}`)}
                            placeholder={t('Type answer option here', 'اكتب خيار الإجابة هنا')}
                            className="w-full resize-none bg-transparent text-center text-sm font-semibold text-[#1A1715] placeholder-[#6E645D] focus:outline-none py-2"
                          />
                          <div />
                        </div>
                      );
                    })}
                  </div>

                  {mcqOptions.length < 6 ? (
                    <button
                      type="button"
                      onClick={handleAddMcqOption}
                      aria-label={t('Add another option card', 'إضافة بطاقة خيار جديدة')}
                      className="flex items-center justify-center rounded-2xl border-2 border-dashed border-[#D6CFC1] bg-white px-3 py-3 text-[#B81104] hover:border-[#B81104] hover:bg-[#FFFACD]/50 shrink-0"
                    >
                      <Plus className="h-5 w-5" aria-hidden="true" />
                    </button>
                  ) : null}
                </div>

                {/* Bottom MCQ Controls (Multiple correct answers + Vertical layout switch) */}
                <div className="flex flex-wrap items-center justify-between gap-3 pt-1">
                  <button
                    type="button"
                    role="switch"
                    aria-checked={mcqMultiCorrect}
                    onClick={handleToggleMultiMode}
                    className="inline-flex items-center gap-2 text-xs font-bold text-[#302521]"
                  >
                    <span>{t('Multiple correct answers:', 'أكثر من إجابة صحيحة:')}</span>
                    {mcqMultiCorrect ? (
                      <ToggleRight className="h-6 w-6 text-[#16845B]" aria-hidden="true" />
                    ) : (
                      <ToggleLeft className="h-6 w-6 text-[#6E645D]" aria-hidden="true" />
                    )}
                  </button>

                  <button
                    type="button"
                    onClick={() => setMcqVerticalLayout((prev) => !prev)}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-[#D6CFC1] bg-white px-3 py-1.5 text-xs font-bold text-[#302521] hover:border-[#B81104] hover:text-[#B81104]"
                  >
                    <LayoutList className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>
                      {mcqVerticalLayout
                        ? t('Switch to horizontal cards', 'التبديل للبطاقات الأفقية')
                        : t('Switch to vertical layout', 'التبديل للتخطيط العمودي')}
                    </span>
                  </button>
                </div>
              </>
            )}
          </div>
        )}
      </div>

      {/* Queued Draft Questions Strip (when building a multi-question assignment/quiz) */}
      {queuedQuestions.length > 0 && targetItemId === 'new' ? (
        <div className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/45 p-3 space-y-2">
          <div className="flex items-center justify-between text-xs font-extrabold text-[#960D03]">
            <span>
              {t(`Queued Questions (${queuedQuestions.length})`, `الأسئلة المضافة للمسودة (${queuedQuestions.length})`)}
            </span>
            <span>{summarizeTemplateTypes(queuedQuestions)}</span>
          </div>
          <div className="flex flex-wrap gap-2">
            {queuedQuestions.map((q, qIdx) => (
              <span
                key={q.id}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[#E9DBA9] bg-white px-2.5 py-1 text-[11px] font-bold text-[#302521]"
              >
                <span className="text-[#B81104]">Q{qIdx + 1} · {q.type}:</span>
                <span className="max-w-[180px] truncate">{q.prompt}</span>
                <button
                  type="button"
                  onClick={() =>
                    setQueuedQuestions((prev) => prev.filter((item) => item.id !== q.id))
                  }
                  aria-label={t(`Remove queued question ${qIdx + 1}`, `إزالة السؤال ${qIdx + 1}`)}
                  className="text-[#C93636] hover:text-[#9E1C0E]"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {builderError ? (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-xl border border-[#C93636]/30 bg-[#FFE9E5] px-3.5 py-2.5 text-xs font-semibold text-[#9E1C0E]"
        >
          <AlertCircle className="h-4 w-4 shrink-0" aria-hidden="true" />
          <span>{builderError}</span>
        </div>
      ) : null}

      {/* Studio Action Buttons */}
      <div className="flex flex-wrap items-center justify-end gap-2.5">
        {targetItemId === 'new' ? (
          <button
            type="button"
            onClick={handleQueueQuestion}
            className="inline-flex items-center gap-1.5 rounded-xl border border-[#E5DCCF] bg-white px-4 py-2.5 text-xs font-bold text-[#302521] hover:border-[#B81104]"
          >
            <Plus className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
            <span>{t('Add Question & Next', 'إضافة سؤال ومتابعة')}</span>
          </button>
        ) : null}

        <button
          type="submit"
          className="inline-flex items-center gap-2 rounded-xl bg-[#B81104] px-5 py-2.5 text-xs sm:text-sm font-bold text-[#FFFACD] hover:bg-[#960D03]"
        >
          <FilePlus2 className="w-4 h-4" aria-hidden="true" />
          <span>
            {targetItemId === 'new'
              ? targetType === 'assignment'
                ? t('Create & Publish Assignment', 'إنشاء ونشر التكليف')
                : t('Create & Publish Quiz', 'إنشاء ونشر الاختبار')
              : targetType === 'assignment'
                ? t('Append Question to Assignment', 'حفظ السؤال في التكليف')
                : t('Append Question to Quiz', 'حفظ السؤال في الاختبار')}
          </span>
        </button>
      </div>
    </form>
  );
}

/**
 * Interactive Assessment Runner for both Course Assignments and Quizzes/Exams.
 * Renders MCQ (single/multi), True/False cards, inline Fill-in-the-blanks,
 * 3000-char Open ended Written responses (routed to Staff Grade Review), and Match pairs.
 */
export function WaygroundPlayer({
  item,
  itemType = 'quiz', // 'assignment' | 'quiz'
  isStaff = false,
  onSubmitted,
}) {
  const { lang, t, profile, setData, showToast } = useCohort();
  const [answers, setAnswers] = useState({});
  const [result, setResult] = useState(null);

  useEffect(() => {
    setResult(null);
  }, [item?.id]);

  if (!item || !item.questions?.length) {
    return null;
  }

  const handleSelectMcqOption = (q, optIdx) => {
    setAnswers((prev) => {
      if (q.multipleCorrect) {
        const existing = Array.isArray(prev[q.id]) ? prev[q.id] : [];
        const next = existing.includes(optIdx)
          ? existing.filter((i) => i !== optIdx)
          : [...existing, optIdx];
        return { ...prev, [q.id]: next };
      }
      return { ...prev, [q.id]: optIdx };
    });
  };

  const handleSubmitAttempt = () => {
    let earned = 0;
    let autoMax = 0;
    let hasWritten = false;
    const writtenItems = [];
    const perQuestion = {};

    item.questions.forEach((q, idx) => {
      const pts = q.points || 0;

      if (q.type === 'Written') {
        hasWritten = true;
        const text = String(answers[q.id] || '').trim();
        if (text) {
          writtenItems.push({ q, idx, text });
        }
        perQuestion[q.id] = {
          status: text
            ? t('Submitted for TA/Staff review', 'مرسل للتصحيح اليدوي')
            : t('No text entered', 'لم تتم الإجابة'),
          earned: 0,
          max: pts,
        };
      } else if (q.type === 'Fill in the blanks') {
        autoMax += pts;
        const expectedList = q.blanks || [''];
        const userMap = answers[q.id] || {};
        const blankMatches = expectedList.map((expected, bIdx) =>
          isBlankCorrect(expected, userMap[bIdx])
        );
        const correctCount = blankMatches.filter(Boolean).length;
        const qEarned = expectedList.length ? Math.round((pts * correctCount) / expectedList.length) : 0;
        earned += qEarned;
        perQuestion[q.id] = {
          status:
            correctCount === expectedList.length
              ? t('Exact match', 'مطابقة صحيحة')
              : `${correctCount}/${expectedList.length} ${t('blanks', 'فراغات')}`,
          earned: qEarned,
          max: pts,
          blankMatches,
        };
      } else if (q.type === 'Match') {
        autoMax += pts;
        const pairs = q.pairs || [];
        const userMap = answers[q.id] || {};
        const matched = pairs.filter((pair) => userMap[pair.left] === pair.right).length;
        const qEarned = pairs.length ? Math.round((pts * matched) / pairs.length) : 0;
        earned += qEarned;
        perQuestion[q.id] = {
          status: matched === pairs.length ? t('All matched', 'كل الأزواج صحيحة') : `${matched}/${pairs.length}`,
          earned: qEarned,
          max: pts,
        };
      } else if (q.type === 'MCQ' && q.multipleCorrect) {
        autoMax += pts;
        const expected = getMcqCorrectIndices(q).slice().sort((a, b) => a - b);
        const picked = (Array.isArray(answers[q.id]) ? answers[q.id] : []).slice().sort((a, b) => a - b);
        const exact =
          expected.length === picked.length && expected.every((val, i) => val === picked[i]);
        const qEarned = exact ? pts : 0;
        earned += qEarned;
        perQuestion[q.id] = {
          status: exact ? t('Correct', 'إجابة صحيحة') : t('Check selections', 'تحقق من الاختيارات'),
          earned: qEarned,
          max: pts,
        };
      } else {
        autoMax += pts;
        const expectedIdx = getMcqCorrectIndices(q)[0];
        const correct = answers[q.id] === expectedIdx;
        if (correct) earned += pts;
        perQuestion[q.id] = {
          status: correct ? t('Correct', 'إجابة صحيحة') : t('Incorrect', 'إجابة غير صحيحة'),
          earned: correct ? pts : 0,
          max: pts,
        };
      }
    });

    setResult({ itemId: item.id, earned, autoMax, hasWritten, perQuestion });

    if (!isStaff && writtenItems.length > 0) {
      setData((prev) => ({
        ...prev,
        gradeReviews: [
          ...writtenItems.map((entry) => ({
            id: `gr-${Date.now()}-${entry.idx}`,
            student: profile.name,
            course: item.course,
            assessment: `${item.title} · Q${entry.idx + 1} (Written)`,
            score: 0,
            status: 'Needs review',
            feedback: `Student response: "${entry.text}"`,
          })),
          ...prev.gradeReviews,
        ],
      }));
    }

    if (!isStaff && itemType === 'assignment') {
      const pct = autoMax > 0 && !hasWritten ? Math.round((earned / autoMax) * 100) : item.grade;
      setData((prev) => ({
        ...prev,
        assignments: prev.assignments.map((asg) =>
          asg.id === item.id
            ? {
                ...asg,
                submitted: true,
                status: hasWritten ? 'Submitted' : 'Graded',
                grade: pct,
                submittedAt: 'Just now',
                submissionNote: `Interactive submission: ${earned}/${autoMax} auto pts${
                  writtenItems.length ? ` · ${writtenItems.length} written answer(s) routed to TA review` : ''
                }`,
              }
            : asg
        ),
      }));
    }

    showToast(
      itemType === 'assignment' && !isStaff
        ? t(
            `Submitted "${item.title}": ${earned}/${autoMax} auto pts${hasWritten ? ' + written response queued for review.' : '.'}`,
            `تم تسليم "${item.title}": ${earned}/${autoMax} نقطة تلقائية.`
          )
        : t(
            `Recorded attempt: ${earned}/${autoMax} auto-graded pts.`,
            `تم تسجيل النتيجة: ${earned}/${autoMax} نقطة تلقائية.`
          )
    );

    if (onSubmitted) {
      onSubmitted({ earned, autoMax, hasWritten });
    }
  };

  return (
    <div className="rounded-2xl border border-[#E9DBA9] bg-white p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#EFE7DA] pb-3">
        <div>
          <span className="text-[10px] font-extrabold uppercase tracking-wider text-[#B81104]">
            {isStaff
              ? t('TA / Faculty Interactive Preview', 'معاينة المعيد والمحاضر')
              : itemType === 'assignment'
                ? t('Interactive Assignment', 'حل التكليف التفاعلي')
                : t('Interactive Quiz', 'تنفيذ الاختبار التفاعلي')}
          </span>
          <h4 className="text-sm sm:text-base font-extrabold text-[#1A1715]">
            {item.course} · {lang === 'ar' ? item.titleAr : item.title}
          </h4>
        </div>

        <button
          type="button"
          onClick={() => {
            setAnswers({});
            setResult(null);
          }}
          className="inline-flex items-center gap-1 rounded-xl border border-[#E5DCCF] bg-[#FCFBF6] px-2.5 py-1.5 text-[11px] font-bold text-[#6E645D] hover:text-[#B81104]"
        >
          <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
          <span>{t('Reset Answers', 'إعادة')}</span>
        </button>
      </div>

      <div className="space-y-4">
        {item.questions.map((q, idx) => {
          const qResult = result?.itemId === item.id ? result.perQuestion?.[q.id] : null;

          return (
            <div
              key={q.id}
              className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-3"
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="rounded-lg bg-[#B81104] px-2.5 py-0.5 text-[11px] font-extrabold text-[#FFFACD]">
                    Q{idx + 1} · {q.type === 'Written' ? t('Open ended', 'مقالي') : q.type}
                  </span>
                  {q.multipleCorrect ? (
                    <span className="rounded-md bg-[#FFFACD] px-2 py-0.5 text-[10px] font-bold text-[#960D03]">
                      {t('Multi-select', 'اختيارات متعددة')}
                    </span>
                  ) : null}
                  <span className="text-xs font-bold text-[#6E645D] tabular-nums">
                    {q.points} {t('pts', 'نقاط')}
                  </span>
                </div>

                {qResult ? (
                  <span className="rounded-full bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-0.5 text-[11px] font-bold text-[#960D03] tabular-nums">
                    {qResult.status} ({qResult.earned}/{qResult.max})
                  </span>
                ) : null}
              </div>

              {q.type === 'Fill in the blanks' ? (
                <div className="space-y-2">
                  {renderTemplatePromptWithBlanks(
                    q.prompt,
                    answers[q.id] || {},
                    (blankIdx, val) =>
                      setAnswers((prev) => ({
                        ...prev,
                        [q.id]: {
                          ...(prev[q.id] || {}),
                          [blankIdx]: val,
                        },
                      })),
                    qResult,
                    t
                  )}
                  {qResult ? (
                    <p className="text-[11px] font-semibold text-[#6E645D]">
                      {t('Accepted key:', 'الإجابة النموذجية:')}{' '}
                      <span className="text-[#16845B] font-bold">
                        {(q.blanks || []).join(' , ')}
                      </span>
                    </p>
                  ) : null}
                </div>
              ) : (
                <p className="text-sm font-bold text-[#1A1715]">{q.prompt}</p>
              )}

              {q.type === 'Written' ? (
                <div className="space-y-2">
                  <div className="relative">
                    <textarea
                      rows={4}
                      maxLength={q.maxLength || 3000}
                      value={answers[q.id] || ''}
                      onChange={(e) =>
                        setAnswers((prev) => ({ ...prev, [q.id]: e.target.value }))
                      }
                      placeholder={t('Students type their open-ended response here...', 'اكتب إجابتك المقالية التفصيلية هنا...')}
                      className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3.5 py-2.5 text-xs sm:text-sm text-[#1A1715] focus:border-[#B81104] focus:outline-none"
                    />
                    <span className="block text-end text-[11px] font-semibold text-[#6E645D] tabular-nums mt-1">
                      {(answers[q.id] || '').length} / {q.maxLength || 3000}{' '}
                      {t('character limit', 'حد الأحرف')}
                    </span>
                  </div>
                  {q.rubric ? (
                    <p className="rounded-lg bg-[#FFFACD]/50 border border-[#E9DBA9] px-3 py-1.5 text-[11px] text-[#6E645D]">
                      <strong className="text-[#960D03]">{t('Rubric:', 'معيار التصحيح:')}</strong> {q.rubric}
                    </p>
                  ) : null}
                </div>
              ) : q.type === 'Match' ? (
                <div className="space-y-2">
                  {(q.pairs || []).map((pair) => {
                    const targets = (q.pairs || []).map((p) => p.right);
                    const chosen = answers[q.id]?.[pair.left] || '';
                    const isMatchedRight = Boolean(qResult) && chosen === pair.right;
                    return (
                      <div
                        key={pair.left}
                        className={`flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-xl border px-3.5 py-2.5 text-xs ${
                          isMatchedRight
                            ? 'border-[#16845B] bg-[#E8F5EC]/70'
                            : 'border-[#E8E3D9] bg-white'
                        }`}
                      >
                        <span className="font-bold text-[#1A1715]">{pair.left}</span>
                        <select
                          aria-label={t(`Match for ${pair.left}`, `توصيل ${pair.left}`)}
                          value={chosen}
                          onChange={(e) =>
                            setAnswers((prev) => ({
                              ...prev,
                              [q.id]: {
                                ...(prev[q.id] || {}),
                                [pair.left]: e.target.value,
                              },
                            }))
                          }
                          className="rounded-xl border border-[#D6CFC1] bg-[#FDFBF7] px-3 py-1.5 text-xs font-semibold text-[#1A1715]"
                        >
                          <option value="">{t('Select matching target...', 'اختر التطابق...')}</option>
                          {targets.map((target) => (
                            <option key={target} value={target}>
                              {target}
                            </option>
                          ))}
                        </select>
                      </div>
                    );
                  })}
                </div>
              ) : q.type !== 'Fill in the blanks' ? (
                /* MCQ & True/False Cohort option cards */
                <div
                  className={`grid gap-2.5 ${
                    q.layout === 'vertical'
                      ? 'grid-cols-1'
                      : q.type === 'True/False' || (q.options || []).length === 2
                        ? 'grid-cols-1 sm:grid-cols-2'
                        : 'grid-cols-1 sm:grid-cols-2 xl:grid-cols-4'
                  }`}
                >
                  {(q.options || []).map((opt, optIdx) => {
                    const selected = q.multipleCorrect
                      ? Array.isArray(answers[q.id]) && answers[q.id].includes(optIdx)
                      : answers[q.id] === optIdx;
                    const cardColor = CARD_PALETTES[optIdx % CARD_PALETTES.length];
                    return (
                      <button
                        key={`${q.id}-${optIdx}`}
                        type="button"
                        onClick={() => handleSelectMcqOption(q, optIdx)}
                        aria-pressed={selected}
                        className={`relative rounded-xl border-2 p-3.5 text-start text-xs sm:text-sm font-bold transition flex items-center justify-between gap-2 ${
                          selected
                            ? 'bg-[#FFFACD] border-[#B81104] text-[#960D03] ring-2 ring-[#B81104] shadow-sm'
                            : `${cardColor} text-[#1A1715] hover:border-[#B81104]/50`
                        }`}
                      >
                        <span>{opt}</span>
                        <span
                          className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full border ${
                            selected
                              ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD]'
                              : 'border-[#D6CFC1] bg-white text-transparent'
                          }`}
                        >
                          <Check className="h-3.5 w-3.5" aria-hidden="true" />
                        </span>
                      </button>
                    );
                  })}
                </div>
              ) : null}
            </div>
          );
        })}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 pt-1">
        <button
          type="button"
          onClick={handleSubmitAttempt}
          className="inline-flex items-center gap-2 rounded-xl bg-[#B81104] px-5 py-2.5 text-xs sm:text-sm font-bold text-[#FFFACD] hover:bg-[#960D03]"
        >
          {itemType === 'assignment' && !isStaff ? (
            <Send className="h-4 w-4" aria-hidden="true" />
          ) : (
            <Play className="h-4 w-4" aria-hidden="true" />
          )}
          <span>
            {isStaff
              ? t('Check Auto-Graded Preview', 'فحص التصحيح التلقائي')
              : itemType === 'assignment'
                ? t('Submit Interactive Assignment', 'تسليم التكليف التفاعلي')
                : t('Submit & Grade Quiz', 'تسليم وتصحيح الاختبار')}
          </span>
        </button>

        {result?.itemId === item.id ? (
          <div className="inline-flex items-center gap-2 rounded-xl bg-[#E8F5EC] border border-[#16845B]/30 px-3.5 py-2 text-xs font-extrabold text-[#16845B] tabular-nums">
            <ClipboardCheck className="h-4 w-4" aria-hidden="true" />
            <span>
              {t('Auto Score:', 'النتيجة التلقائية:')} {result.earned} / {result.autoMax} pts
              {result.hasWritten
                ? ` · ${t('Written sent for TA review', '+ المقالي أُرسل للمراجعة')}`
                : ''}
            </span>
          </div>
        ) : null}
      </div>
    </div>
  );
}
