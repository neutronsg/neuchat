import {
  isQaPairDirty,
  sortByCreatedAtDesc,
  shouldBlockEditSessionLeave,
  shouldShowQaProcessingHint,
} from '../utils/editSession';

describe('knowledge base edit session utils', () => {
  describe('sortByCreatedAtDesc', () => {
    it('sorts items with latest created_at first', () => {
      const items = [
        { id: 1, created_at: '2026-02-01T10:00:00Z' },
        { id: 2, created_at: '2026-02-03T10:00:00Z' },
        { id: 3, created_at: '2026-02-02T10:00:00Z' },
      ];

      const sorted = sortByCreatedAtDesc(items);
      expect(sorted.map(item => item.id)).toEqual([2, 3, 1]);
      expect(items.map(item => item.id)).toEqual([1, 2, 3]);
    });
  });

  describe('shouldBlockEditSessionLeave', () => {
    it('returns true when edit session is active on qa tab', () => {
      expect(
        shouldBlockEditSessionLeave({
          isEditSessionActive: true,
          activeTab: 'qa',
        })
      ).toBe(true);
    });

    it('returns false when edit session is inactive', () => {
      expect(
        shouldBlockEditSessionLeave({
          isEditSessionActive: false,
          activeTab: 'qa',
        })
      ).toBe(false);
    });

    it('returns false when current tab is not qa', () => {
      expect(
        shouldBlockEditSessionLeave({
          isEditSessionActive: true,
          activeTab: 'documents',
        })
      ).toBe(false);
    });
  });

  describe('isQaPairDirty', () => {
    it('returns true for newly added temp qa item', () => {
      expect(
        isQaPairDirty({
          qaPair: { id: 'temp-1', question: 'Q1', answer: 'A1' },
          originalQaPair: null,
        })
      ).toBe(true);
    });

    it('returns true when existing qa question or answer changed', () => {
      expect(
        isQaPairDirty({
          qaPair: { id: 10, question: 'Q2', answer: 'A1' },
          originalQaPair: { id: 10, question: 'Q1', answer: 'A1' },
        })
      ).toBe(true);
    });

    it('returns false when existing qa item is unchanged', () => {
      expect(
        isQaPairDirty({
          qaPair: { id: 10, question: 'Q1', answer: 'A1' },
          originalQaPair: { id: 10, question: 'Q1', answer: 'A1' },
        })
      ).toBe(false);
    });
  });

  describe('shouldShowQaProcessingHint', () => {
    it('returns true when qa editing is disabled by processing state', () => {
      expect(shouldShowQaProcessingHint({ canEdit: false })).toBe(true);
    });

    it('returns false when qa editing is enabled', () => {
      expect(shouldShowQaProcessingHint({ canEdit: true })).toBe(false);
    });
  });
});
