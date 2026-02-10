import {
  appendImageMarkdown,
  getQaEditorClass,
  QA_IMAGE_BUTTON_ICON_CLASS,
  QA_IMAGE_BUTTON_SIZE,
  QA_IMAGE_BUTTON_TYPE,
  QA_RENDERED_IMAGE_LIMIT_CLASS,
  QA_EDITOR_HIDE_TOOLBAR_CLASS,
} from '../utils/qaEditor';

describe('knowledge base qa editor utils', () => {
  describe('appendImageMarkdown', () => {
    it('returns only image markdown when content is empty', () => {
      expect(
        appendImageMarkdown({
          content: '',
          fileUrl: 'https://cdn.example.com/image.png',
        })
      ).toBe('![image](https://cdn.example.com/image.png)');
    });

    it('appends image markdown on a new line when content exists', () => {
      expect(
        appendImageMarkdown({
          content: 'How to reset password?',
          fileUrl: 'https://cdn.example.com/image.png',
        })
      ).toBe(
        'How to reset password?\n![image](https://cdn.example.com/image.png)'
      );
    });
  });

  describe('getQaEditorClass', () => {
    it('returns hide-toolbar class by default', () => {
      expect(getQaEditorClass()).toBe(QA_EDITOR_HIDE_TOOLBAR_CLASS);
    });

    it('returns empty class when hideToolbar is false', () => {
      expect(getQaEditorClass({ hideToolbar: false })).toBe('');
    });
  });

  describe('image button style config', () => {
    it('uses button type to avoid form submit side effects', () => {
      expect(QA_IMAGE_BUTTON_TYPE).toBe('button');
    });

    it('uses sm as button size', () => {
      expect(QA_IMAGE_BUTTON_SIZE).toBe('sm');
    });

    it('uses a larger and softer icon class', () => {
      expect(QA_IMAGE_BUTTON_ICON_CLASS).toContain('text-base');
      expect(QA_IMAGE_BUTTON_ICON_CLASS).toContain('text-n-slate-10');
    });
  });

  describe('rendered image limit class', () => {
    it('constrains displayed image width and height', () => {
      expect(QA_RENDERED_IMAGE_LIMIT_CLASS).toContain('[&_img]:max-h-60');
      expect(QA_RENDERED_IMAGE_LIMIT_CLASS).toContain('[&_img]:max-w-full');
    });
  });
});
