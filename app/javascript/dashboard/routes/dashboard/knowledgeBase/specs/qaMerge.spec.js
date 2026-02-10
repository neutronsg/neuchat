import {
  findDuplicateQuestion,
  hasMeaningfulQuestion,
  mergeImportedQaPairs,
  normalizeQuestionForComparison,
} from '../utils/qaMerge';

describe('knowledge base qa merge utils', () => {
  describe('normalizeQuestionForComparison', () => {
    it('normalizes case and spaces', () => {
      expect(
        normalizeQuestionForComparison('  How   Do   I   Reset Password?  ')
      ).toBe('how do i reset password?');
    });

    it('removes markdown images before comparison', () => {
      expect(
        normalizeQuestionForComparison(
          'How to reset password? ![proof](https://cdn.example.com/image.png)'
        )
      ).toBe('how to reset password?');
    });
  });

  describe('hasMeaningfulQuestion', () => {
    it('returns false when question only contains image markdown', () => {
      expect(
        hasMeaningfulQuestion(
          '![only-image](https://cdn.example.com/image.png)'
        )
      ).toBe(false);
    });

    it('returns true when question has text content', () => {
      expect(
        hasMeaningfulQuestion(
          'How to reset password? ![proof](https://cdn.example.com/image.png)'
        )
      ).toBe(true);
    });
  });

  describe('findDuplicateQuestion', () => {
    const qaPairs = [
      {
        id: 1,
        question:
          'How to reset password? ![proof](https://cdn.example.com/image.png)',
      },
      { id: 2, question: 'How to update billing info?' },
    ];

    it('finds duplicate based on normalized question text', () => {
      const duplicate = findDuplicateQuestion({
        qaPairs,
        question: ' how to RESET password? ',
      });

      expect(duplicate?.id).toBe(1);
    });

    it('ignores current item id when editing', () => {
      const duplicate = findDuplicateQuestion({
        qaPairs,
        question: 'How to update billing info?',
        excludeId: 2,
      });

      expect(duplicate).toBeNull();
    });
  });

  describe('mergeImportedQaPairs', () => {
    it('updates answer when question already exists and adds non-existing ones', () => {
      const currentQaPairs = [
        {
          id: 101,
          question: 'How to reset password?',
          answer: 'Old answer',
          created_at: '2026-02-08T10:00:00.000Z',
          updated_at: '2026-02-08T10:00:00.000Z',
        },
      ];

      const importedQaPairs = [
        {
          question: '  how to RESET password?  ',
          answer: 'New merged answer',
        },
        {
          question: 'How to contact support?',
          answer: 'Email support@example.com',
        },
      ];

      const result = mergeImportedQaPairs({
        currentQaPairs,
        importedQaPairs,
        nowIso: '2026-02-09T10:00:00.000Z',
        buildTempQa: (qa, index) => ({
          id: `temp-import-${index}`,
          question: qa.question,
          answer: qa.answer,
          created_at: '2026-02-09T10:00:00.000Z',
          updated_at: '2026-02-09T10:00:00.000Z',
        }),
      });

      expect(result.addedCount).toBe(1);
      expect(result.updatedCount).toBe(1);
      expect(result.qaPairs[0].id).toBe('temp-import-0');
      expect(result.qaPairs[1].id).toBe(101);
      expect(result.qaPairs[1].question).toBe('How to reset password?');
      expect(result.qaPairs[1].answer).toBe('New merged answer');
      expect(result.qaPairs[1].updated_at).toBe('2026-02-09T10:00:00.000Z');
    });
  });
});
