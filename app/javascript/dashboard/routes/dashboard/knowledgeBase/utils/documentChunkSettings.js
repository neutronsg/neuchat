export const DEFAULT_CHUNK_SETTINGS_FORM = Object.freeze({
  separator: '\\n\\n',
  maxTokens: '1024',
  chunkOverlap: '50',
  preProcessingRules: {
    removeExtraSpaces: false,
    removeUrlsEmails: false,
  },
});

const cloneDefaultRules = () => ({
  removeExtraSpaces:
    DEFAULT_CHUNK_SETTINGS_FORM.preProcessingRules.removeExtraSpaces,
  removeUrlsEmails:
    DEFAULT_CHUNK_SETTINGS_FORM.preProcessingRules.removeUrlsEmails,
});

export const createDefaultChunkSettingsForm = () => ({
  separator: DEFAULT_CHUNK_SETTINGS_FORM.separator,
  maxTokens: DEFAULT_CHUNK_SETTINGS_FORM.maxTokens,
  chunkOverlap: DEFAULT_CHUNK_SETTINGS_FORM.chunkOverlap,
  preProcessingRules: cloneDefaultRules(),
});

export const escapeChunkSettingSeparator = value =>
  String(value ?? '')
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n')
    .replace(/\t/g, '\\t');

export const unescapeChunkSettingSeparator = value =>
  String(value ?? '')
    .replace(/\\r/g, '\r')
    .replace(/\\n/g, '\n')
    .replace(/\\t/g, '\t');

export const createChunkSettingsFormFromApi = chunkSettings => ({
  separator: escapeChunkSettingSeparator(chunkSettings?.separator ?? '\n\n'),
  maxTokens: String(chunkSettings?.max_tokens ?? 1024),
  chunkOverlap: String(chunkSettings?.chunk_overlap ?? 50),
  preProcessingRules: {
    removeExtraSpaces:
      !!chunkSettings?.pre_processing_rules?.remove_extra_spaces,
    removeUrlsEmails: !!chunkSettings?.pre_processing_rules?.remove_urls_emails,
  },
});

export const serializeChunkSettingsForm = form => ({
  separator: unescapeChunkSettingSeparator(form.separator),
  max_tokens: Number(form.maxTokens),
  chunk_overlap: Number(form.chunkOverlap),
  pre_processing_rules: {
    remove_extra_spaces: !!form.preProcessingRules.removeExtraSpaces,
    remove_urls_emails: !!form.preProcessingRules.removeUrlsEmails,
  },
});

export const validateChunkSettingsForm = ({ form, t }) => {
  const separator = String(form.separator ?? '').trim();
  const maxTokens = Number(form.maxTokens);
  const chunkOverlap = Number(form.chunkOverlap);

  if (!separator) {
    return t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.SEPARATOR_REQUIRED');
  }

  if (!Number.isInteger(maxTokens) || maxTokens <= 0) {
    return t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.MAX_TOKENS_INVALID');
  }

  if (!Number.isInteger(chunkOverlap) || chunkOverlap < 0) {
    return t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.CHUNK_OVERLAP_INVALID');
  }

  if (chunkOverlap > maxTokens) {
    return t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.CHUNK_OVERLAP_TOO_LARGE');
  }

  return '';
};
