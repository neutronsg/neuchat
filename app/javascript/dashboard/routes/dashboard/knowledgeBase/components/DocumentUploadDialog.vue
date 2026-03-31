<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChunkSettingsForm from './ChunkSettingsForm.vue';
import {
  createDefaultChunkSettingsForm,
  serializeChunkSettingsForm,
  validateChunkSettingsForm,
} from '../utils/documentChunkSettings';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
  acceptedFileTypes: {
    type: String,
    default: '',
  },
  maxFileSizeMb: {
    type: Number,
    default: 100,
  },
});

const emit = defineEmits(['uploaded']);

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const dialogRef = ref(null);
const fileInputRef = ref(null);
const selectedFile = ref(null);
const chunkSettingsForm = ref(createDefaultChunkSettingsForm());

const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);
const isUploading = computed(() => uiFlags.value.isCreating);
const selectedFileName = computed(() => selectedFile.value?.name || '');
const disableConfirmButton = computed(
  () => isUploading.value || !selectedFile.value
);

const resetForm = () => {
  selectedFile.value = null;
  chunkSettingsForm.value = createDefaultChunkSettingsForm();
  if (fileInputRef.value) {
    fileInputRef.value.value = '';
  }
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const triggerFilePicker = () => {
  fileInputRef.value?.click();
};

const onFileChange = event => {
  const [file] = event.target.files || [];
  if (!file) return;

  if (file.size > props.maxFileSizeMb * 1024 * 1024) {
    showAlert(
      t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.FILE_TOO_LARGE', {
        size: props.maxFileSizeMb,
      })
    );
    event.target.value = '';
    return;
  }

  selectedFile.value = file;
};

const handleReset = () => {
  chunkSettingsForm.value = createDefaultChunkSettingsForm();
};

const handleSubmit = async () => {
  if (!selectedFile.value) {
    showAlert(t('KNOWLEDGE_BASE.CHUNK_SETTINGS_ERRORS.FILE_REQUIRED'));
    return;
  }

  const validationError = validateChunkSettingsForm({
    form: chunkSettingsForm.value,
    t,
  });
  if (validationError) {
    showAlert(validationError);
    return;
  }

  try {
    await store.dispatch('knowledgeBases/createDocument', {
      knowledgeBaseId: props.knowledgeBaseId,
      file: selectedFile.value,
      name: selectedFile.value.name,
      chunkSettings: serializeChunkSettingsForm(chunkSettingsForm.value),
    });
    showAlert(t('KNOWLEDGE_BASE.DOCUMENT_UPLOADED'));
    emit('uploaded');
    close();
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.UPLOAD_FAILED'));
  }
};

const handleClose = () => {
  resetForm();
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="$t('KNOWLEDGE_BASE.UPLOAD_DOCUMENT')"
    :confirm-button-label="$t('KNOWLEDGE_BASE.UPLOAD_DOCUMENT')"
    :disable-confirm-button="disableConfirmButton"
    :is-loading="isUploading"
    @confirm="handleSubmit"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <div class="rounded-xl border border-n-weak bg-n-background p-5">
        <div class="mb-3 text-sm font-medium text-n-slate-12">
          {{ $t('KNOWLEDGE_BASE.SELECT_FILE') }}
        </div>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <Button
            :label="$t('KNOWLEDGE_BASE.SELECT_FILE')"
            variant="outline"
            color="slate"
            type="button"
            @click="triggerFilePicker"
          />
          <span class="text-sm text-n-slate-11">
            {{ selectedFileName || $t('KNOWLEDGE_BASE.NO_FILE_SELECTED') }}
          </span>
        </div>
        <input
          ref="fileInputRef"
          type="file"
          class="hidden"
          :accept="acceptedFileTypes"
          @change="onFileChange"
        />
      </div>

      <ChunkSettingsForm
        v-model="chunkSettingsForm"
        :disabled="isUploading"
        @reset="handleReset"
      />
    </div>
  </Dialog>
</template>
