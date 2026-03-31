export const QA_EDITOR_HIDE_TOOLBAR_CLASS =
  '[&_.ProseMirror-menubar]:!hidden [&_.ProseMirror-menubar-wrapper]:!gap-0';
export const QA_EDITOR_MENU_OPTIONS = ['imageUpload'];
export const QA_IMAGE_BUTTON_TYPE = 'button';
export const QA_IMAGE_BUTTON_SIZE = 'sm';
export const QA_IMAGE_BUTTON_ICON_CLASS =
  'i-lucide-image-plus text-base text-n-slate-10 dark:text-n-slate-10';
export const QA_RENDERED_IMAGE_LIMIT_CLASS =
  '[&_img]:max-h-60 [&_img]:max-w-full [&_img]:w-auto [&_img]:object-contain [&_img]:rounded-md';

export const getQaEditorClass = ({ hideToolbar = true } = {}) =>
  hideToolbar ? QA_EDITOR_HIDE_TOOLBAR_CLASS : '';

export const appendImageMarkdown = ({ content, fileUrl }) => {
  const imageMarkdown = `![image](${fileUrl})`;
  const trimmedContent = String(content || '').trimEnd();

  if (!trimmedContent) return imageMarkdown;

  return `${trimmedContent}\n${imageMarkdown}`;
};
