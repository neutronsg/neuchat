<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useAI } from 'dashboard/composables/useAI';
import AILoader from './AILoader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    AILoader,
    NextButton,
  },
  props: {
    aiOption: {
      type: String,
      required: true,
    },
    isPrivateNote: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['close', 'applyText'],
  setup() {
    const { formatMessage } = useMessageFormatter();
    const { draftMessage, processEvent, recordAnalytics } = useAI();
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
        ? this.$t(`INTEGRATION_SETTINGS.OPEN_AI.WITH_AI`, {
            option: this.$t(
              `INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.${translationKey}`
            ),
          })
        : '';
    },
    // 判断是否应该显示"Use this suggestion"按钮
    // Private Note模式：所有功能都显示应用按钮
    // Reply模式：summarize不显示应用按钮，其他功能显示
    shouldShowApplyButton() {
      if (this.isPrivateNote) {
        return true; // Private Note模式下所有功能都有应用按钮
      }
      return this.aiOption !== 'summarize'; // Reply模式下summarize没有应用按钮
    },
    // 判断是否应该显示确认按钮（Reply模式下的summarize）
    shouldShowConfirmButton() {
      return !this.isPrivateNote && this.aiOption === 'summarize';
    },
    // 应用按钮的文本
    applyButtonText() {
      return this.$t(
        'INTEGRATION_SETTINGS.OPEN_AI.ASSISTANCE_MODAL.BUTTONS.APPLY'
      );
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
      this.generatedContent = await this.processEvent(type);
      this.isGenerating = false;
    },
    applyText() {
      this.recordAnalytics(this.aiOption);
      this.$emit('applyText', this.generatedContent);
      this.onClose();
    },
    confirmAndClose() {
      // Reply模式下summarize的确认按钮，只关闭弹窗
      this.recordAnalytics(this.aiOption);
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
          {{ $t('INTEGRATION_SETTINGS.OPEN_AI.ASSISTANCE_MODAL.DRAFT_TITLE') }}
        </h4>
        <p v-dompurify-html="formatMessage(draftMessage, false)" />
        <h4 class="mt-1 text-base text-n-slate-12">
          {{
            $t('INTEGRATION_SETTINGS.OPEN_AI.ASSISTANCE_MODAL.GENERATED_TITLE')
          }}
        </h4>
      </div>
      <div>
        <AILoader v-if="isGenerating" />
        <p v-else v-dompurify-html="formatMessage(generatedContent, false)" />
      </div>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="
            $t('INTEGRATION_SETTINGS.OPEN_AI.ASSISTANCE_MODAL.BUTTONS.CANCEL')
          "
          @click.prevent="onClose"
        />
        <NextButton
          v-if="shouldShowApplyButton"
          type="submit"
          :disabled="!generatedContent"
          :label="applyButtonText"
        />
        <NextButton
          v-if="shouldShowConfirmButton"
          type="button"
          :disabled="!generatedContent"
          label="Confirm"
          @click.prevent="confirmAndClose"
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
