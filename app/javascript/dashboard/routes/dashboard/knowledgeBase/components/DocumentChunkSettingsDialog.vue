<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChunkSettingsForm from './ChunkSettingsForm.vue';
import {
  createChunkSettingsFormFromApi,
  createDefaultChunkSettingsForm,
  serializeChunkSettingsForm,
  validateChunkSettingsForm,
} from '../utils/documentChunkSettings';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});

const emit = defineEmits(['saved']);

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const dialogRef = ref(null);
const currentDocument = ref(null);
const chunkSettingsForm = ref(createDefaultChunkSettingsForm());
const isLoading = ref(false);
const isSaving = ref(false);
const isEditable = ref(true);
const unsupportedReason = ref('');
const loadError = ref('');

const resetLocalState = () => {
  currentDocument.value = null;
  chunkSettingsForm.value = createDefaultChunkSettingsForm();
  isLoading.value = false;
  isSaving.value = false;
  isEditable.value = true;
  unsupportedReason.value = '';
  loadError.value = '';
};

const open = async document => {
  resetLocalState();
  currentDocument.value = document;
  dialogRef.value?.open();
  isLoading.value = true;

  try {
    const response = await store.dispatch(
      'knowledgeBases/fetchDocumentChunkSettings',
      {
        knowledgeBaseId: props.knowledgeBaseId,
        documentId: document.id,
      }
    );
    const { chunk_settings: chunkSettings } = response;
    isEditable.value = !!chunkSettings?.editable;
    unsupportedReason.value = chunkSettings?.reason || '';

    if (isEditable.value) {
      chunkSettingsForm.value = createChunkSettingsFormFromApi(chunkSettings);
    }
  } catch (error) {
    loadError.value =
      error.message || t('KNOWLEDGE_BASE.CHUNK_SETTINGS_LOAD_FAILED');
    showAlert(loadError.value);
  } finally {
    isLoading.value = false;
  }
};

const close = () => {
  dialogRef.value?.close();
};

const handleReset = () => {
  if (!isEditable.value) return;

  chunkSettingsForm.value = createDefaultChunkSettingsForm();
};

const handleSubmit = async () => {
  if (!currentDocument.value || !isEditable.value) return;

  const validationError = validateChunkSettingsForm({
    form: chunkSettingsForm.value,
    t,
  });
  if (validationError) {
    showAlert(validationError);
    return;
  }

  isSaving.value = true;
  try {
    await store.dispatch('knowledgeBases/updateDocumentChunkSettings', {
      knowledgeBaseId: props.knowledgeBaseId,
      documentId: currentDocument.value.id,
      chunkSettings: serializeChunkSettingsForm(chunkSettingsForm.value),
    });
    showAlert(t('KNOWLEDGE_BASE.CHUNK_SETTINGS_SAVED'));
    emit('saved');
    close();
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.CHUNK_SETTINGS_SAVE_FAILED'));
  } finally {
    isSaving.value = false;
  }
};

const handleClose = () => {
  resetLocalState();
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="$t('KNOWLEDGE_BASE.CHUNK_SETTINGS_BUTTON')"
    :confirm-button-label="$t('KNOWLEDGE_BASE.SAVE_CHANGES')"
    :disable-confirm-button="
      isLoading || isSaving || !isEditable || !!loadError
    "
    :is-loading="isSaving"
    @confirm="handleSubmit"
    @close="handleClose"
  >
    <div v-if="isLoading" class="py-6 text-center text-sm text-n-slate-11">
      {{ $t('KNOWLEDGE_BASE.LOADING') }}
    </div>

    <div
      v-else-if="loadError"
      class="rounded-xl border border-n-ruby-5 bg-n-ruby-2 p-5 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </div>

    <div
      v-else-if="!isEditable"
      class="rounded-xl border border-n-weak bg-n-background p-5 text-sm text-n-slate-11"
    >
      {{
        $t('KNOWLEDGE_BASE.CHUNK_SETTINGS_UNSUPPORTED', {
          reason: unsupportedReason || 'unsupported_mode',
        })
      }}
    </div>

    <ChunkSettingsForm
      v-else
      v-model="chunkSettingsForm"
      :disabled="isSaving"
      @reset="handleReset"
    />
  </Dialog>
</template>
