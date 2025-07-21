<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useNeuAI } from 'dashboard/composables/useNeuAI';
import NeuAILoader from './NeuAILoader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NeuAILoader,
    NextButton,
  },
  props: {
    aiOption: {
      type: String,
      required: true,
    },
  },
  emits: ['close', 'applyText'],
  setup() {
    const { formatMessage } = useMessageFormatter();
    const { draftMessage, processEvent, recordAnalytics } = useNeuAI();
    return { draftMessage, processEvent, recordAnalytics, formatMessage };
  },
  data() {
    return {
      generatedContent: '',
      isGenerating: true,
    };
  },
  computed: {
    headerTitle() {
      const translationKey = this.aiOption?.toUpperCase();
      return translationKey
        ? this.$t(`INTEGRATION_SETTINGS.NEUAI.WITH_AI`, {
            option: this.$t(
              `INTEGRATION_SETTINGS.NEUAI.OPTIONS.${translationKey}`
            ),
          })
        : '';
    },
    isReadOnlyMode() {
      return this.aiOption === 'summarize_readonly';
    },
  },
  mounted() {
    this.generateAIContent(this.aiOption);
  },

  methods: {
    onClose() {
      this.$emit('close');
    },

    async generateAIContent(type = 'rephrase') {
      this.isGenerating = true;
      // Convert readonly type to regular type for API call
      const apiType = type === 'summarize_readonly' ? 'summarize' : type;
      this.generatedContent = await this.processEvent(apiType);
      this.isGenerating = false;
    },
    applyText() {
      this.recordAnalytics(this.aiOption);
      this.$emit('applyText', this.generatedContent);
      this.onClose();
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <woot-modal-header :header-title="headerTitle" />
    <form
      class="flex flex-col w-full modal-content"
      @submit.prevent="applyText"
    >
      <div v-if="draftMessage" class="w-full">
        <h4 class="mt-1 text-base text-n-slate-12">
          {{ $t('INTEGRATION_SETTINGS.NEUAI.ASSISTANCE_MODAL.DRAFT_TITLE') }}
        </h4>
        <p v-dompurify-html="formatMessage(draftMessage, false)" />
        <h4 class="mt-1 text-base text-n-slate-12">
          {{
            $t('INTEGRATION_SETTINGS.NEUAI.ASSISTANCE_MODAL.GENERATED_TITLE')
          }}
        </h4>
      </div>
      <div>
        <NeuAILoader v-if="isGenerating" />
        <p v-else v-dompurify-html="formatMessage(generatedContent, false)" />
      </div>

      <div class="flex flex-row gap-2 justify-end px-0 py-2 w-full">
        <NextButton
          faded
          slate
          type="reset"
          :label="
            $t('INTEGRATION_SETTINGS.NEUAI.ASSISTANCE_MODAL.BUTTONS.CANCEL')
          "
          @click.prevent="onClose"
        />
        <NextButton
          v-if="!isReadOnlyMode"
          type="submit"
          :disabled="!generatedContent"
          :label="
            $t('INTEGRATION_SETTINGS.NEUAI.ASSISTANCE_MODAL.BUTTONS.APPLY')
          "
        />
        <NextButton
          v-if="isReadOnlyMode"
          type="button"
          :disabled="!generatedContent"
          :label="
            $t('INTEGRATION_SETTINGS.NEUAI.ASSISTANCE_MODAL.BUTTONS.CONFIRM')
          "
          @click="onClose"
        />
      </div>
    </form>
  </div>
</template>

<style lang="scss" scoped>
.modal-content {
  @apply pt-2 px-8 pb-8;
}

.container {
  width: 100%;
}
</style>
