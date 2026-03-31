const MARKDOWN_IMAGE_REGEX = /!\[[^\]]*]\([^)]*\)/g;
const MARKDOWN_LINK_REGEX = /\[([^\]]+)\]\([^)]+\)/g;

export const normalizeQuestionForComparison = question =>
  String(question || '')
    .replace(MARKDOWN_IMAGE_REGEX, ' ')
    .replace(MARKDOWN_LINK_REGEX, '$1')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

export const hasMeaningfulQuestion = question =>
  normalizeQuestionForComparison(question).length > 0;

export const findDuplicateQuestion = ({ qaPairs, question, excludeId }) => {
  const normalizedQuestion = normalizeQuestionForComparison(question);
  if (!normalizedQuestion) return null;

  return (
    qaPairs.find(qa => {
      if (excludeId !== undefined && String(qa.id) === String(excludeId)) {
        return false;
      }
      return normalizeQuestionForComparison(qa.question) === normalizedQuestion;
    }) || null
  );
};

export const mergeImportedQaPairs = ({
  currentQaPairs,
  importedQaPairs,
  nowIso = new Date().toISOString(),
  buildTempQa,
}) => {
  const existingQaPairs = currentQaPairs.map(qa => ({ ...qa }));
  const createdQaPairs = [];
  const normalizedQuestionMap = new Map();
  let updatedCount = 0;

  existingQaPairs.forEach(qa => {
    const key = normalizeQuestionForComparison(qa.question);
    if (key && !normalizedQuestionMap.has(key)) {
      normalizedQuestionMap.set(key, qa);
    }
  });

  importedQaPairs.forEach(importedQa => {
    const key = normalizeQuestionForComparison(importedQa.question);
    if (!key) return;

    const matchedQa = normalizedQuestionMap.get(key);
    if (matchedQa) {
      matchedQa.answer = importedQa.answer;
      matchedQa.updated_at = nowIso;
      updatedCount += 1;
      return;
    }

    const newQa = buildTempQa
      ? buildTempQa(importedQa, createdQaPairs.length)
      : { ...importedQa };
    createdQaPairs.push(newQa);
    normalizedQuestionMap.set(key, newQa);
  });

  return {
    qaPairs: [...createdQaPairs, ...existingQaPairs],
    addedCount: createdQaPairs.length,
    updatedCount,
  };
};
