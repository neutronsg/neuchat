import { computed, onMounted } from 'vue';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { NEUAI_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import NeuAIAPI from 'dashboard/api/integrations/neuaiapi';

/**
 * Cleans and normalizes a list of labels.
 * @param {string} labels - A comma-separated string of labels.
 * @returns {string[]} An array of cleaned and unique labels.
 */
const cleanLabels = labels => {
  return labels
    .toLowerCase() // Set it to lowercase
    .split(',') // split the string into an array
    .filter(label => label.trim()) // remove any empty strings
    .map(label => label.trim()) // trim the words
    .filter((label, index, self) => self.indexOf(label) === index);
};

/**
 * A composable function for NeuAI-related operations in the dashboard.
 * @returns {Object} An object containing NeuAI-related methods and computed properties.
 */
export function useNeuAI() {
  const store = useStore();
  const getters = useStoreGetters();
  const { t } = useI18n();

  /**
   * Computed property for UI flags.
   * @type {import('vue').ComputedRef<Object>}
   */
  const uiFlags = computed(() => getters['integrations/getUIFlags'].value);

  const appIntegrations = useMapGetter('integrations/getAppIntegrations');
  const currentChat = useMapGetter('getSelectedChat');
  const replyMode = useMapGetter('draftMessages/getReplyEditorMode');

  /**
   * Computed property for the NeuAI integration.
   * @type {import('vue').ComputedRef<Object|undefined>}
   */
  const neuaiIntegration = computed(
    () =>
      appIntegrations.value.find(
        integration => integration.id === 'neuai' && !!integration.hooks.length
      )?.hooks[0]
  );

  /**
   * Computed property to check if NeuAI integration is enabled.
   * @type {import('vue').ComputedRef<boolean>}
   */
  const isNeuAIIntegrationEnabled = computed(() => !!neuaiIntegration.value);

  /**
   * Computed property to check if label suggestion feature is enabled.
   * @type {import('vue').ComputedRef<boolean>}
   */
  const isLabelSuggestionFeatureEnabled = computed(() => {
    if (neuaiIntegration.value) {
      const { settings = {} } = neuaiIntegration.value || {};
      return settings.label_suggestion;
    }
    return false;
  });

  /**
   * Computed property to check if app integrations are being fetched.
   * @type {import('vue').ComputedRef<boolean>}
   */
  const isFetchingAppIntegrations = computed(() => uiFlags.value.isFetching);

  /**
   * Computed property for the hook ID.
   * @type {import('vue').ComputedRef<string|undefined>}
   */
  const hookId = computed(() => neuaiIntegration.value?.id);

  /**
   * Computed property for the conversation ID.
   * @type {import('vue').ComputedRef<string|undefined>}
   */
  const conversationId = computed(() => currentChat.value?.id);

  /**
   * Computed property for the draft key.
   * @type {import('vue').ComputedRef<string>}
   */
  const draftKey = computed(
    () => `draft-${conversationId.value}-${replyMode.value}`
  );

  /**
   * Computed property for the draft message.
   * @type {import('vue').ComputedRef<string>}
   */
  const draftMessage = computed(() =>
    getters['draftMessages/get'].value(draftKey.value)
  );

  /**
   * Fetches integrations if they haven't been loaded yet.
   * @returns {Promise<void>}
   */
  const fetchIntegrationsIfRequired = async () => {
    if (!appIntegrations.value.length) {
      await store.dispatch('integrations/get');
    }
  };

  /**
   * Records analytics for NeuAI-related events.
   * @param {string} type - The type of event.
   * @param {Object} payload - Additional data for the event.
   * @returns {Promise<void>}
   */
  const recordAnalytics = async (type, payload) => {
    const event = NEUAI_EVENTS[type.toUpperCase()];
    if (event) {
      useTrack(event, {
        type,
        provider: 'neuai',
        ...payload,
      });
    }
  };

  /**
   * Fetches label suggestions for the current conversation.
   * @returns {Promise<string[]>} An array of suggested labels.
   */
  const fetchLabelSuggestions = async () => {
    if (!conversationId.value) return [];

    try {
      const result = await NeuAIAPI.processEvent({
        type: 'label_suggestion',
        hookId: hookId.value,
        conversationId: conversationId.value,
      });

      const {
        data: { message: labels },
      } = result;

      return cleanLabels(labels);
    } catch {
      return [];
    }
  };

  /**
   * Processes a NeuAI event, such as rephrasing content.
   * @param {string} [type='rephrase'] - The type of NeuAI event to process.
   * @returns {Promise<string>} The generated message or an empty string if an error occurs.
   */
  const processEvent = async (type = 'rephrase') => {
    try {
      const result = await NeuAIAPI.processEvent({
        hookId: hookId.value,
        type,
        content: draftMessage.value,
        conversationId: conversationId.value,
      });
      const {
        data: { message: generatedMessage },
      } = result;
      return generatedMessage;
    } catch (error) {
      const errorData = error.response.data.error;
      const errorMessage =
        errorData?.error?.message ||
        t('INTEGRATION_SETTINGS.NEUAI.GENERATE_ERROR');
      useAlert(errorMessage);
      return '';
    }
  };

  onMounted(() => {
    fetchIntegrationsIfRequired();
  });

  return {
    draftMessage,
    uiFlags,
    appIntegrations,
    currentChat,
    replyMode,
    isNeuAIIntegrationEnabled,
    isLabelSuggestionFeatureEnabled,
    isFetchingAppIntegrations,
    fetchIntegrationsIfRequired,
    recordAnalytics,
    fetchLabelSuggestions,
    processEvent,
  };
}
