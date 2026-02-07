import knowledgeBasesModule from '../../knowledgeBases';

describe('knowledgeBases module mutations', () => {
  describe('setQaPairs', () => {
    it('keeps newest qa pairs on top by created_at', () => {
      const state = { qaPairs: [] };
      const qaPairs = [
        { id: 1, created_at: '2026-02-01T10:00:00Z' },
        { id: 2, created_at: '2026-02-03T10:00:00Z' },
        { id: 3, created_at: '2026-02-02T10:00:00Z' },
      ];

      knowledgeBasesModule.mutations.setQaPairs(state, qaPairs);

      expect(state.qaPairs.map(item => item.id)).toEqual([2, 3, 1]);
    });
  });

  describe('addQaPair', () => {
    it('adds newly created qa pair to the top of the list', () => {
      const state = {
        qaPairs: [{ id: 1, created_at: '2026-02-01T10:00:00Z' }],
      };
      const qaPair = { id: 2, created_at: '2026-02-03T10:00:00Z' };

      knowledgeBasesModule.mutations.addQaPair(state, qaPair);

      expect(state.qaPairs.map(item => item.id)).toEqual([2, 1]);
    });
  });

  describe('setDocuments', () => {
    it('keeps newest documents on top by created_at', () => {
      const state = { documents: [] };
      const documents = [
        { id: 10, created_at: '2026-02-01T10:00:00Z' },
        { id: 11, created_at: '2026-02-03T10:00:00Z' },
        { id: 12, created_at: '2026-02-02T10:00:00Z' },
      ];

      knowledgeBasesModule.mutations.setDocuments(state, documents);

      expect(state.documents.map(item => item.id)).toEqual([11, 12, 10]);
    });
  });
});
