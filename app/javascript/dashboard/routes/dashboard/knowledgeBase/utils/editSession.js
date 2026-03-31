export const toTimestamp = value => {
  const timestamp = Date.parse(value || '');
  return Number.isNaN(timestamp) ? 0 : timestamp;
};

export const sortByCreatedAtDesc = items =>
  [...items].sort(
    (a, b) => toTimestamp(b.created_at) - toTimestamp(a.created_at)
  );

export const shouldBlockEditSessionLeave = ({
  isEditSessionActive,
  activeTab,
}) => Boolean(isEditSessionActive && activeTab === 'qa');

export const shouldShowQaProcessingHint = ({ canEdit }) => !canEdit;

export const isQaPairDirty = ({ qaPair, originalQaPair }) => {
  const isTempItem = String(qaPair?.id || '').startsWith('temp-');
  if (isTempItem) return true;
  if (!originalQaPair) return false;

  return (
    qaPair.question !== originalQaPair.question ||
    qaPair.answer !== originalQaPair.answer
  );
};
