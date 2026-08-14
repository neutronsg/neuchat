<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useNeuAI } from 'dashboard/composables/useNeuAI';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
  fullWidth: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const isGenerating = ref(false);
const { isNeuAIIntegrationEnabled, generateContactNote } = useNeuAI();

const generateAndSaveNote = async () => {
  isGenerating.value = true;
  try {
    const content = await generateContactNote(props.contactId);

    if (content) {
      await store.dispatch('contactNotes/create', {
        contactId: props.contactId,
        content,
        noteType: 'neuai',
      });
      useAlert(t('CONTACTS_LAYOUT.SIDEBAR.NOTES.AI_SUCCESS'));
    }
  } catch {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.NOTES.AI_SAVE_ERROR'));
  } finally {
    isGenerating.value = false;
  }
};
</script>

<template>
  <div
    v-if="isNeuAIIntegrationEnabled"
    :class="{ 'flex justify-end px-4 py-2 border-b border-n-weak': fullWidth }"
  >
    <Button
      variant="link"
      color="blue"
      size="sm"
      icon="i-ph-magic-wand"
      :label="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.GENERATE_WITH_AI')"
      :is-loading="isGenerating"
      :disabled="isGenerating"
      @click="generateAndSaveNote"
    />
  </div>
</template>
