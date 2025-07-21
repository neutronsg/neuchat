import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import {
  ICON_AI_ASSIST,
  ICON_AI_GRAMMAR,
  // ICON_AI_EXPAND,
  // ICON_AI_SHORTEN,
  ICON_AI_SUMMARY,
} from 'dashboard/helper/commandbar/icons';
import { CMD_NEUAI_ASSIST } from 'dashboard/helper/commandbar/events';

/**
 * Creates NeuAI assist actions for draft messages
 * @param {Function} t - Translation function
 * @returns {Array} Array of NeuAI assist actions
 */
export const createDraftMessageNeuAIAssistActions = t => {
  return [
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.REPHRASE'),
      key: 'rephrase',
      icon: ICON_AI_ASSIST,
    },
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.FIX_SPELLING_GRAMMAR'),
      key: 'fix_spelling_grammar',
      icon: ICON_AI_GRAMMAR,
    },
    // {
    //   label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.EXPAND'),
    //   key: 'expand',
    //   icon: ICON_AI_EXPAND,
    // },
    // {
    //   label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.SHORTEN'),
    //   key: 'shorten',
    //   icon: ICON_AI_SHORTEN,
    // },
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.MAKE_FRIENDLY'),
      key: 'make_friendly',
      icon: ICON_AI_ASSIST,
    },
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.MAKE_FORMAL'),
      key: 'make_formal',
      icon: ICON_AI_ASSIST,
    },
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.SIMPLIFY'),
      key: 'simplify',
      icon: ICON_AI_ASSIST,
    },
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.TRANSLATE'),
      key: 'translate',
      icon: ICON_AI_ASSIST,
    },
  ];
};

/**
 * Creates NeuAI assist actions for non-draft messages
 * @param {Function} t - Translation function
 * @param {String} replyMode - Current reply mode
 * @returns {Array} Array of NeuAI assist actions
 */
export const createNonDraftMessageNeuAIAssistActions = (t, replyMode) => {
  if (replyMode === REPLY_EDITOR_MODES.REPLY) {
    return [
      {
        label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.REPLY_SUGGESTION'),
        key: 'reply_suggestion',
        icon: ICON_AI_ASSIST,
      },
      {
        label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.SUMMARIZE'),
        key: 'summarize_readonly',
        icon: ICON_AI_SUMMARY,
      },
    ];
  }
  return [
    {
      label: t('INTEGRATION_SETTINGS.NEUAI.OPTIONS.SUMMARIZE'),
      key: 'summarize',
      icon: ICON_AI_SUMMARY,
    },
  ];
};

/**
 * Creates formatted NeuAI assist actions for command bar
 * @param {Object} options - Configuration options
 * @param {Function} options.t - Translation function
 * @param {Ref} options.draftMessage - Draft message ref
 * @param {Ref} options.replyMode - Reply mode ref
 * @param {Object} options.emitter - Event emitter
 * @returns {Array} Formatted NeuAI assist actions
 */
export const createNeuAIAssistActions = ({
  t,
  draftMessage,
  replyMode,
  emitter,
}) => {
  const aiOptions = draftMessage.value
    ? createDraftMessageNeuAIAssistActions(t)
    : createNonDraftMessageNeuAIAssistActions(t, replyMode.value);

  const options = aiOptions.map(item => ({
    id: `neuai-assist-${item.key}`,
    title: item.label,
    parent: 'neuai_assist',
    section: t('COMMAND_BAR.SECTIONS.AI_ASSIST'),
    priority: item,
    icon: item.icon,
    handler: () => emitter.emit(CMD_NEUAI_ASSIST, item.key),
  }));

  return [
    {
      id: 'neuai_assist',
      title: t('COMMAND_BAR.COMMANDS.NEUAI_ASSIST'),
      section: t('COMMAND_BAR.SECTIONS.AI_ASSIST'),
      icon: ICON_AI_ASSIST,
      children: options.map(option => option.id),
    },
    ...options,
  ];
};
