<script>
import { ref } from 'vue';
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useNeuAI } from 'dashboard/composables/useNeuAI';
import NeuAICTAModal from './NeuAICTAModal.vue';
import NeuAIAssistanceModal from './NeuAIAssistanceModal.vue';
import { CMD_NEUAI_ASSIST } from 'dashboard/helper/commandbar/events';
import NeuAIAssistanceCTAButton from './NeuAIAssistanceCTAButton.vue';
import { emitter } from 'shared/helpers/mitt';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
    NeuAIAssistanceModal,
    NeuAICTAModal,
    NeuAIAssistanceCTAButton,
  },
  emits: ['replaceText'],
  setup(props, { emit }) {
    const { uiSettings, updateUISettings } = useUISettings();

    const { isNeuAIIntegrationEnabled, draftMessage, recordAnalytics } =
      useNeuAI();

    const { isAdmin } = useAdmin();

    const initialMessage = ref('');

    const initializeMessage = draftMsg => {
      initialMessage.value = draftMsg;
    };
    const keyboardEvents = {
      '$mod+KeyZ': {
        action: () => {
          if (initialMessage.value) {
            emit('replaceText', initialMessage.value);
            initialMessage.value = '';
          }
        },
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);

    return {
      uiSettings,
      updateUISettings,
      isAdmin,
      initialMessage,
      initializeMessage,
      recordAnalytics,
      isNeuAIIntegrationEnabled,
      draftMessage,
    };
  },
  data: () => ({
    showAIAssistanceModal: false,
    showAICtaModal: false,
    aiOption: '',
  }),
  computed: {
    ...mapGetters({
      isAChatwootInstance: 'globalConfig/isAChatwootInstance',
    }),
    isAICTAModalDismissed() {
      return this.uiSettings.is_open_ai_cta_modal_dismissed;
    },
    // Display a AI CTA button for admins if the AI integration has not been added yet and the AI assistance modal has not been dismissed.
    shouldShowAIAssistCTAButtonForAdmin() {
      return (
        this.isAdmin &&
        !this.isNeuAIIntegrationEnabled &&
        !this.isAICTAModalDismissed &&
        this.isAChatwootInstance
      );
    },
    // Display a AI CTA button for agents and other admins who have not yet opened the AI assistance modal.
    shouldShowAIAssistCTAButton() {
      return this.isNeuAIIntegrationEnabled && !this.isAICTAModalDismissed;
    },
  },

  mounted() {
    emitter.on(CMD_NEUAI_ASSIST, this.onAIAssist);
    this.initializeMessage(this.draftMessage);
  },

  methods: {
    hideAIAssistanceModal() {
      this.recordAnalytics('DISMISS_AI_SUGGESTION', {
        aiOption: this.aiOption,
      });
      this.showAIAssistanceModal = false;
    },
    openAIAssist() {
      // Dismiss the CTA modal if it is not dismissed
      if (!this.isAICTAModalDismissed) {
        this.updateUISettings({
          is_open_ai_cta_modal_dismissed: true,
        });
      }
      this.initializeMessage(this.draftMessage);
      const ninja = document.querySelector('ninja-keys');
      ninja.open({ parent: 'neuai_assist' });
    },
    hideAICtaModal() {
      this.showAICtaModal = false;
    },
    openAICta() {
      this.showAICtaModal = true;
    },
    onAIAssist(option) {
      this.aiOption = option;
      this.showAIAssistanceModal = true;
    },
    insertText(message) {
      this.$emit('replaceText', message);
    },
  },
};
</script>

<template>
  <div>
    <div v-if="isNeuAIIntegrationEnabled" class="relative">
      <NeuAIAssistanceCTAButton
        v-if="shouldShowAIAssistCTAButton"
        @open="openAIAssist"
      />
      <NextButton
        v-else
        v-tooltip.top-end="$t('INTEGRATION_SETTINGS.NEUAI.AI_ASSIST')"
        icon="i-ph-magic-wand"
        slate
        faded
        sm
        @click="openAIAssist"
      />
      <woot-modal
        v-model:show="showAIAssistanceModal"
        :on-close="hideAIAssistanceModal"
      >
        <NeuAIAssistanceModal
          :ai-option="aiOption"
          @apply-text="insertText"
          @close="hideAIAssistanceModal"
        />
      </woot-modal>
    </div>
    <div v-else-if="shouldShowAIAssistCTAButtonForAdmin" class="relative">
      <NeuAIAssistanceCTAButton @click="openAICta" />
      <woot-modal v-model:show="showAICtaModal" :on-close="hideAICtaModal">
        <NeuAICTAModal @close="hideAICtaModal" />
      </woot-modal>
    </div>
  </div>
</template>
