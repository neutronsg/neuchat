<script setup>
import { ref, computed, watch, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import KBSectionCard from 'dashboard/components-next/KnowledgeBase/KBSectionCard.vue';
import KBStatusPill from 'dashboard/components-next/KnowledgeBase/KBStatusPill.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import {
  isQaPairDirty,
  shouldShowQaProcessingHint,
  sortByCreatedAtDesc,
} from '../utils/editSession';
import {
  appendImageMarkdown,
  getQaEditorClass,
  QA_IMAGE_BUTTON_ICON_CLASS,
  QA_IMAGE_BUTTON_SIZE,
  QA_IMAGE_BUTTON_TYPE,
  QA_EDITOR_MENU_OPTIONS,
  QA_RENDERED_IMAGE_LIMIT_CLASS,
} from '../utils/qaEditor';
import {
  findDuplicateQuestion,
  hasMeaningfulQuestion,
  mergeImportedQaPairs,
} from '../utils/qaMerge';

const props = defineProps({
  knowledgeBaseId: {
    type: [String, Number],
    required: true,
  },
});
const emit = defineEmits(['editSessionChange']);

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const isEditMode = ref(false);
const qaDialog = ref(null);
const importDocxGuideDialog = ref(null);
const isEditing = ref(false);
const editingId = ref(null);
const form = ref({ question: '', answer: '' });
const docxFileInput = ref(null);
const questionImageInput = ref(null);
const answerImageInput = ref(null);
const isImportingDocx = ref(false);
const isUploadingQuestionImage = ref(false);
const isUploadingAnswerImage = ref(false);

const QA_SEPARATOR = '------';
const QA_IMAGE_MAX_SIZE_MB = 4;
const docxGuideExampleClass =
  'mt-2 whitespace-pre-wrap text-xs leading-5 text-n-slate-12';
const qaEditorClass =
  `${getQaEditorClass()} ${QA_RENDERED_IMAGE_LIMIT_CLASS}`.trim();

const localQaPairs = ref([]);
const deletedQaPairIds = ref([]);

const qaPairs = computed(() => store.getters['knowledgeBases/getQaPairs']);
const originalQaPairMap = computed(() => {
  const map = {};
  qaPairs.value.forEach(qa => {
    map[qa.id] = qa;
  });
  return map;
});
const uiFlags = computed(() => store.getters['knowledgeBases/getUIFlags']);
const qaDocumentStatus = computed(
  () => store.getters['knowledgeBases/getQaDocumentStatus']
);
const isProcessing = computed(
  () => store.getters['knowledgeBases/isQaDocumentProcessing']
);

const canEdit = computed(() => !isProcessing.value);
const displayedQaPairs = computed(() =>
  isEditMode.value ? sortByCreatedAtDesc(localQaPairs.value) : qaPairs.value
);
const qaTotalCount = computed(() => displayedQaPairs.value.length);
const hasData = computed(() => displayedQaPairs.value.length > 0);
const showProcessingHint = computed(() =>
  shouldShowQaProcessingHint({ canEdit: canEdit.value })
);
const qaHeaderDescription = computed(() =>
  hasData.value
    ? t('KNOWLEDGE_BASE.QA_TOTAL_COUNT', { count: qaTotalCount.value })
    : ''
);

const isDirtyQa = qa =>
  isQaPairDirty({
    qaPair: qa,
    originalQaPair: originalQaPairMap.value[qa.id],
  });

const statusLabel = computed(() => {
  const status = qaDocumentStatus.value?.display_status;
  if (!status || status === 'unknown') return '';
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(`KNOWLEDGE_BASE.STATUS_${status.toUpperCase()}`) || status;
});

const formatDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const formatRichContent = content =>
  new MessageFormatter(content || '').formattedMessage;
const getQaDisplayNumberByIndex = index => qaTotalCount.value - index;
const getQaDisplayNumberById = qaId => {
  const index = displayedQaPairs.value.findIndex(
    qa => String(qa.id) === String(qaId)
  );
  return index === -1 ? null : getQaDisplayNumberByIndex(index);
};
const editingQaNumber = computed(() => {
  if (!isEditing.value || !editingId.value) return null;
  return getQaDisplayNumberById(editingId.value);
});
const qaDialogTitle = computed(() => {
  if (!isEditing.value) return t('KNOWLEDGE_BASE.ADD_QA');

  const numberLabel = editingQaNumber.value
    ? t('KNOWLEDGE_BASE.QA_NUMBER', {
        number: editingQaNumber.value,
      })
    : '';

  return numberLabel
    ? `${t('KNOWLEDGE_BASE.EDIT_QA')} ${numberLabel}`
    : t('KNOWLEDGE_BASE.EDIT_QA');
});
const qaDocxGuideExample = computed(() =>
  t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_EXAMPLE')
);
const isUploadingAnyImage = computed(
  () => isUploadingQuestionImage.value || isUploadingAnswerImage.value
);
const canSaveQaForm = computed(
  () =>
    hasMeaningfulQuestion(form.value.question) &&
    form.value.answer.trim().length > 0 &&
    !isUploadingAnyImage.value
);

const createLocalEditSnapshot = () =>
  sortByCreatedAtDesc(JSON.parse(JSON.stringify(qaPairs.value)));

const beginEditSessionFromStore = () => {
  localQaPairs.value = createLocalEditSnapshot();
  deletedQaPairIds.value = [];
  isEditMode.value = true;
};

const enterEditMode = () => {
  beginEditSessionFromStore();
};

const exitEditMode = () => {
  isEditMode.value = false;
  localQaPairs.value = [];
  deletedQaPairIds.value = [];
};

const openAddModal = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = false;
  qaDialog.value?.open();
};

const openEditModal = qa => {
  form.value = { question: qa.question, answer: qa.answer };
  editingId.value = qa.id;
  isEditing.value = true;
  qaDialog.value?.open();
};

const closeDialog = () => {
  qaDialog.value?.close();
};

const onDialogClose = () => {
  form.value = { question: '', answer: '' };
  editingId.value = null;
  isEditing.value = false;
};

const saveQaPair = () => {
  const qaScope = isEditMode.value ? localQaPairs.value : qaPairs.value;

  if (!hasMeaningfulQuestion(form.value.question)) {
    showAlert(t('KNOWLEDGE_BASE.QA_QUESTION_TEXT_REQUIRED'));
    return;
  }

  const duplicateQa = findDuplicateQuestion({
    qaPairs: qaScope,
    question: form.value.question,
    excludeId: editingId.value,
  });
  if (duplicateQa) {
    const duplicateNumber = getQaDisplayNumberById(duplicateQa.id);
    showAlert(
      duplicateNumber
        ? t('KNOWLEDGE_BASE.QA_DUPLICATE_QUESTION_WITH_NUMBER', {
            number: duplicateNumber,
          })
        : t('KNOWLEDGE_BASE.QA_DUPLICATE_QUESTION')
    );
    return;
  }

  if (editingId.value) {
    const index = localQaPairs.value.findIndex(q => q.id === editingId.value);
    if (index !== -1) {
      localQaPairs.value[index] = {
        ...localQaPairs.value[index],
        ...form.value,
        updated_at: new Date().toISOString(),
      };
    }
  } else {
    const newQa = {
      id: `temp-${Date.now()}`,
      ...form.value,
      updated_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
    };

    if (!isEditMode.value) {
      // If adding from view mode, initialize local state with current store data.
      beginEditSessionFromStore();
    }

    localQaPairs.value.unshift(newQa);
  }
  closeDialog();
};

const saveChanges = async () => {
  store.commit('knowledgeBases/setUIFlag', { isSyncing: true });
  try {
    // 1. Handle Deletions
    const deletePromises = deletedQaPairIds.value.map(id =>
      store.dispatch('knowledgeBases/deleteQaPair', {
        knowledgeBaseId: props.knowledgeBaseId,
        qaPairId: id,
      })
    );

    // 2. Handle Creations and Updates
    const updatePromises = localQaPairs.value.map(qa => {
      if (typeof qa.id === 'string' && qa.id.startsWith('temp-')) {
        // Create new
        return store.dispatch('knowledgeBases/createQaPair', {
          knowledgeBaseId: props.knowledgeBaseId,
          data: { question: qa.question, answer: qa.answer },
        });
      }
      // Update existing
      const original = qaPairs.value.find(q => q.id === qa.id);
      if (
        original &&
        (original.question !== qa.question || original.answer !== qa.answer)
      ) {
        return store.dispatch('knowledgeBases/updateQaPair', {
          knowledgeBaseId: props.knowledgeBaseId,
          qaPairId: qa.id,
          data: { question: qa.question, answer: qa.answer },
        });
      }

      return Promise.resolve();
    });

    await Promise.all([...deletePromises, ...updatePromises]);

    // 3. Sync
    await store.dispatch('knowledgeBases/syncQaPairs', props.knowledgeBaseId);

    // 4. Refresh list
    await store.dispatch('knowledgeBases/fetchQaPairs', {
      knowledgeBaseId: props.knowledgeBaseId,
    });

    showAlert(t('KNOWLEDGE_BASE.SYNC_SUCCESS'));
    exitEditMode();
  } catch (error) {
    showAlert(error.message);
  } finally {
    store.commit('knowledgeBases/setUIFlag', { isSyncing: false });
  }
};

const deleteQaPair = async qa => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('KNOWLEDGE_BASE.CONFIRM_DELETE_QA'))) return;

  if (typeof qa.id === 'string' && qa.id.startsWith('temp-')) {
    // Remove from local list if it's a temp item
    localQaPairs.value = localQaPairs.value.filter(q => q.id !== qa.id);
  } else {
    // Mark for deletion if it's a persistent item
    localQaPairs.value = localQaPairs.value.filter(q => q.id !== qa.id);
    deletedQaPairIds.value.push(qa.id);
  }
};

const discardEditSession = () => {
  exitEditMode();
};

const triggerDocxImport = () => {
  docxFileInput.value?.click();
};

const openDocxImportGuideDialog = () => {
  importDocxGuideDialog.value?.open();
};

const confirmDocxImportGuide = () => {
  importDocxGuideDialog.value?.close();
  requestAnimationFrame(() => {
    triggerDocxImport();
  });
};

const mergeImportedQaPairsIntoEditSession = importedQaPairs => {
  if (!importedQaPairs.length) {
    return {
      addedCount: 0,
      updatedCount: 0,
    };
  }

  if (!isEditMode.value) {
    beginEditSessionFromStore();
  }

  const timestamp = Date.now();
  const nowIso = new Date().toISOString();
  const mergeResult = mergeImportedQaPairs({
    currentQaPairs: localQaPairs.value,
    importedQaPairs,
    nowIso,
    buildTempQa: (qa, index) => ({
      id: `temp-import-${timestamp}-${index}`,
      question: qa.question,
      answer: qa.answer,
      created_at: nowIso,
      updated_at: nowIso,
    }),
  });

  localQaPairs.value = sortByCreatedAtDesc(mergeResult.qaPairs);
  return mergeResult;
};

const handleDocxImport = async event => {
  const file = event.target.files[0];
  if (!file) return;

  isImportingDocx.value = true;
  try {
    const response = await store.dispatch(
      'knowledgeBases/importQaPairsFromDocx',
      {
        knowledgeBaseId: props.knowledgeBaseId,
        file,
      }
    );
    const mergeResult = mergeImportedQaPairsIntoEditSession(
      response.qa_pairs || []
    );
    const { addedCount, updatedCount } = mergeResult;
    const mergedCount = addedCount + updatedCount;

    if (mergedCount === 0) {
      showAlert(t('KNOWLEDGE_BASE.QA_DOCX_NO_VALID_ITEMS'));
    } else {
      showAlert(
        t('KNOWLEDGE_BASE.QA_DOCX_IMPORTED_TO_EDIT', {
          total: mergedCount,
          added: addedCount,
          updated: updatedCount,
        })
      );
    }
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.QA_DOCX_IMPORT_FAILED'));
  } finally {
    isImportingDocx.value = false;
    event.target.value = '';
  }
};

const clearFileInput = event => {
  event.target.value = '';
};

const appendUploadedImageToField = ({ field, fileUrl }) => {
  form.value[field] = appendImageMarkdown({
    content: form.value[field],
    fileUrl,
  });
};

const uploadImageForField = async ({ file, field }) => {
  if (!checkFileSizeLimit(file, QA_IMAGE_MAX_SIZE_MB)) {
    showAlert(
      t('KNOWLEDGE_BASE.QA_IMAGE_UPLOAD_SIZE_ERROR', {
        size: QA_IMAGE_MAX_SIZE_MB,
      })
    );
    return;
  }

  const isQuestionField = field === 'question';
  if (isQuestionField) {
    isUploadingQuestionImage.value = true;
  } else {
    isUploadingAnswerImage.value = true;
  }

  try {
    const { fileUrl } = await uploadFile(file);
    if (fileUrl) {
      appendUploadedImageToField({ field, fileUrl });
      showAlert(t('KNOWLEDGE_BASE.QA_IMAGE_UPLOAD_SUCCESS'));
    }
  } catch (error) {
    showAlert(error.message || t('KNOWLEDGE_BASE.QA_IMAGE_UPLOAD_FAILED'));
  } finally {
    if (isQuestionField) {
      isUploadingQuestionImage.value = false;
    } else {
      isUploadingAnswerImage.value = false;
    }
  }
};

const onQuestionImageSelected = async event => {
  const file = event.target.files[0];
  clearFileInput(event);
  if (!file) return;

  await uploadImageForField({ file, field: 'question' });
};

const onAnswerImageSelected = async event => {
  const file = event.target.files[0];
  clearFileInput(event);
  if (!file) return;

  await uploadImageForField({ file, field: 'answer' });
};

const openQuestionImagePicker = () => {
  questionImageInput.value?.click();
};

const openAnswerImagePicker = () => {
  answerImageInput.value?.click();
};

watch(isEditMode, isEditingNow => {
  emit('editSessionChange', isEditingNow);
});

onUnmounted(() => {
  emit('editSessionChange', false);
});

defineExpose({ discardEditSession });
</script>

<template>
  <div
    :class="isEditMode ? 'rounded-2xl ring-2 ring-n-amber-9 ring-offset-2' : ''"
  >
    <KBSectionCard
      :title="t('KNOWLEDGE_BASE.QA_TITLE')"
      :description="qaHeaderDescription"
    >
      <template #status>
        <KBStatusPill
          v-if="qaDocumentStatus?.display_status"
          :status="qaDocumentStatus.display_status"
          :label="statusLabel"
        />
        <span
          v-if="isEditMode"
          class="inline-flex items-center rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-semibold text-n-amber-12"
        >
          {{ t('KNOWLEDGE_BASE.EDIT_MODE_ACTIVE') }}
        </span>
      </template>
      <template #actions>
        <div class="flex items-center gap-3">
          <template v-if="isEditMode">
            <div class="flex items-center gap-2">
              <span
                class="inline-flex items-center rounded-md bg-n-amber-3 px-2 py-1 text-xs font-semibold text-n-amber-12"
              >
                {{ t('KNOWLEDGE_BASE.UNSAVED_SESSION') }}
              </span>
              <Button
                :label="t('KNOWLEDGE_BASE.SAVE_CHANGES')"
                :is-loading="uiFlags.isSyncing"
                color="amber"
                @click="saveChanges"
              />
            </div>
            <Button
              :label="t('KNOWLEDGE_BASE.CANCEL_EDIT')"
              variant="outline"
              color="slate"
              @click="exitEditMode"
            />
            <Button
              :label="
                isImportingDocx
                  ? t('KNOWLEDGE_BASE.IMPORTING_DOCX')
                  : t('KNOWLEDGE_BASE.IMPORT_QA_DOCX')
              "
              variant="outline"
              color="slate"
              :is-loading="isImportingDocx"
              :disabled="!canEdit || isImportingDocx"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="openDocxImportGuideDialog"
            />
          </template>
          <template v-else>
            <Button
              v-if="hasData"
              :label="t('KNOWLEDGE_BASE.EDIT')"
              :disabled="!canEdit"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="enterEditMode"
            />
            <Button
              :label="t('KNOWLEDGE_BASE.ADD_QA')"
              :disabled="!canEdit"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="openAddModal"
            />
            <Button
              :label="
                isImportingDocx
                  ? t('KNOWLEDGE_BASE.IMPORTING_DOCX')
                  : t('KNOWLEDGE_BASE.IMPORT_QA_DOCX')
              "
              variant="outline"
              color="slate"
              :is-loading="isImportingDocx"
              :disabled="!canEdit || isImportingDocx"
              :title="!canEdit ? t('KNOWLEDGE_BASE.PROCESSING_HINT') : ''"
              @click="openDocxImportGuideDialog"
            />
          </template>
        </div>
        <input
          ref="docxFileInput"
          type="file"
          class="hidden"
          accept=".docx"
          @change="handleDocxImport"
        />
      </template>

      <p
        v-if="showProcessingHint"
        class="mt-2 rounded-md bg-n-amber-3 px-3 py-2 text-xs font-semibold text-n-amber-12"
      >
        {{ t('KNOWLEDGE_BASE.PROCESSING_HINT') }}
      </p>
      <!-- 编辑模式：列表上方的新增按钮 -->
      <div v-if="isEditMode" class="mb-4">
        <p class="mb-2 text-xs font-medium text-n-amber-12">
          {{ t('KNOWLEDGE_BASE.EDIT_SESSION_HINT') }}
        </p>
        <Button :label="t('KNOWLEDGE_BASE.ADD_QA')" @click="openAddModal" />
      </div>

      <!-- 弹窗 -->
      <Dialog
        ref="qaDialog"
        :title="qaDialogTitle"
        :confirm-button-label="t('KNOWLEDGE_BASE.CONFIRM')"
        :cancel-button-label="t('KNOWLEDGE_BASE.CANCEL')"
        :disable-confirm-button="!canSaveQaForm"
        @confirm="saveQaPair"
        @close="onDialogClose"
      >
        <div class="flex flex-col gap-4">
          <Editor
            v-model="form.question"
            :class="qaEditorClass"
            :label="t('KNOWLEDGE_BASE.QUESTION')"
            :placeholder="t('KNOWLEDGE_BASE.QUESTION_PLACEHOLDER')"
            :max-length="20000"
            :show-character-count="false"
            :enable-canned-responses="false"
            :enable-variables="false"
            :enabled-menu-options="QA_EDITOR_MENU_OPTIONS"
          >
            <template #actions>
              <div class="flex w-full justify-start">
                <Button
                  :icon="QA_IMAGE_BUTTON_ICON_CLASS"
                  :size="QA_IMAGE_BUTTON_SIZE"
                  :type="QA_IMAGE_BUTTON_TYPE"
                  variant="ghost"
                  color="slate"
                  :is-loading="isUploadingQuestionImage"
                  :disabled="isUploadingAnyImage"
                  :aria-label="
                    isUploadingQuestionImage
                      ? t('KNOWLEDGE_BASE.QA_IMAGE_UPLOADING')
                      : t('KNOWLEDGE_BASE.QA_ADD_IMAGE_QUESTION')
                  "
                  :title="
                    isUploadingQuestionImage
                      ? t('KNOWLEDGE_BASE.QA_IMAGE_UPLOADING')
                      : t('KNOWLEDGE_BASE.QA_ADD_IMAGE_QUESTION')
                  "
                  @click="openQuestionImagePicker"
                />
                <input
                  ref="questionImageInput"
                  type="file"
                  class="hidden"
                  accept="image/png, image/jpeg, image/jpg, image/gif, image/webp"
                  @change="onQuestionImageSelected"
                />
              </div>
            </template>
          </Editor>
          <Editor
            v-model="form.answer"
            :class="qaEditorClass"
            :label="t('KNOWLEDGE_BASE.ANSWER')"
            :placeholder="t('KNOWLEDGE_BASE.ANSWER_PLACEHOLDER')"
            :max-length="50000"
            :show-character-count="false"
            :enable-canned-responses="false"
            :enable-variables="false"
            :enabled-menu-options="QA_EDITOR_MENU_OPTIONS"
          >
            <template #actions>
              <div class="flex w-full justify-start">
                <Button
                  :icon="QA_IMAGE_BUTTON_ICON_CLASS"
                  :size="QA_IMAGE_BUTTON_SIZE"
                  :type="QA_IMAGE_BUTTON_TYPE"
                  variant="ghost"
                  color="slate"
                  :is-loading="isUploadingAnswerImage"
                  :disabled="isUploadingAnyImage"
                  :aria-label="
                    isUploadingAnswerImage
                      ? t('KNOWLEDGE_BASE.QA_IMAGE_UPLOADING')
                      : t('KNOWLEDGE_BASE.QA_ADD_IMAGE_ANSWER')
                  "
                  :title="
                    isUploadingAnswerImage
                      ? t('KNOWLEDGE_BASE.QA_IMAGE_UPLOADING')
                      : t('KNOWLEDGE_BASE.QA_ADD_IMAGE_ANSWER')
                  "
                  @click="openAnswerImagePicker"
                />
                <input
                  ref="answerImageInput"
                  type="file"
                  class="hidden"
                  accept="image/png, image/jpeg, image/jpg, image/gif, image/webp"
                  @change="onAnswerImageSelected"
                />
              </div>
            </template>
          </Editor>
          <p class="text-xs text-n-slate-11">
            {{ t('KNOWLEDGE_BASE.QA_IMAGE_UPLOAD_HINT') }}
          </p>
        </div>
      </Dialog>

      <Dialog
        ref="importDocxGuideDialog"
        :title="t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_TITLE')"
        :confirm-button-label="t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_CONFIRM')"
        :cancel-button-label="t('KNOWLEDGE_BASE.CANCEL')"
        @confirm="confirmDocxImportGuide"
      >
        <div class="flex flex-col gap-3 text-sm text-n-slate-11">
          <p class="text-sm text-n-slate-12">
            {{ t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_INTRO') }}
          </p>
          <ul class="list-disc space-y-1 pl-5">
            <li>
              {{
                t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_RULE_1', {
                  separator: QA_SEPARATOR,
                })
              }}
            </li>
            <li>{{ t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_RULE_2') }}</li>
            <li>{{ t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_RULE_3') }}</li>
            <li>{{ t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_RULE_4') }}</li>
          </ul>
          <div class="rounded-md border border-n-weak bg-n-alpha-2 p-3">
            <p class="text-xs font-semibold text-n-slate-12">
              {{ t('KNOWLEDGE_BASE.QA_DOCX_GUIDE_EXAMPLE_TITLE') }}
            </p>
            <div :class="docxGuideExampleClass">{{ qaDocxGuideExample }}</div>
          </div>
        </div>
      </Dialog>

      <div
        v-if="uiFlags.isFetchingQaPairs && !hasData"
        class="py-6 text-center"
      >
        <span class="text-sm text-n-slate-11">{{
          t('KNOWLEDGE_BASE.LOADING')
        }}</span>
      </div>

      <div v-else-if="!hasData" class="py-6 text-center">
        <p class="text-sm text-n-slate-11">
          {{ t('KNOWLEDGE_BASE.NO_QA_PAIRS') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-3">
        <div
          v-for="(qa, index) in displayedQaPairs"
          :key="qa.id"
          class="relative overflow-hidden rounded-xl border px-4 py-4"
          :class="
            isEditMode && isDirtyQa(qa)
              ? 'border-n-amber-8 bg-n-amber-2'
              : 'border-n-weak bg-n-background'
          "
        >
          <span
            class="absolute left-0 top-0 inline-flex items-center rounded-br-md border-b border-r border-n-brand/20 bg-n-brand/10 px-2 py-0.5 text-[11px] font-medium text-n-blue-text"
          >
            {{
              t('KNOWLEDGE_BASE.QA_NUMBER', {
                number: getQaDisplayNumberByIndex(index),
              })
            }}
          </span>
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0 flex-1 pt-3">
              <div
                v-if="isEditMode && isDirtyQa(qa)"
                class="mb-1 flex items-center gap-2"
              >
                <span
                  class="inline-flex items-center rounded-md bg-n-amber-4 px-2 py-0.5 text-[11px] font-semibold text-n-amber-12"
                >
                  {{ t('KNOWLEDGE_BASE.DIRTY_ITEM') }}
                </span>
              </div>
              <div class="text-sm font-semibold text-n-slate-12">
                {{ t('KNOWLEDGE_BASE.QUESTION_PREFIX') }}
              </div>
              <div
                v-dompurify-html="formatRichContent(qa.question)"
                class="prose prose-bubble max-w-none text-sm text-n-slate-12"
                :class="[QA_RENDERED_IMAGE_LIMIT_CLASS]"
              />
              <div class="mt-2 text-sm font-semibold text-n-slate-12">
                {{ t('KNOWLEDGE_BASE.ANSWER_PREFIX') }}
              </div>
              <div
                v-dompurify-html="formatRichContent(qa.answer)"
                class="prose prose-bubble max-w-none text-sm text-n-slate-11"
                :class="[QA_RENDERED_IMAGE_LIMIT_CLASS]"
              />
              <div class="mt-3 flex items-center gap-1 text-xs text-n-slate-11">
                {{ t('KNOWLEDGE_BASE.UPDATED_AT') }}
                {{ formatDateTime(qa.updated_at) }}
                <span
                  v-if="qa.updated_by"
                  class="text-n-slate-12"
                  :title="qa.updated_by.email"
                >
                  {{ t('KNOWLEDGE_BASE.BY') }} {{ qa.updated_by.name }}
                </span>
              </div>
            </div>
            <div v-if="isEditMode" class="flex items-center gap-2 shrink-0">
              <Button
                :label="t('KNOWLEDGE_BASE.EDIT')"
                variant="ghost"
                color="slate"
                @click="openEditModal(qa)"
              />
              <Button
                :label="t('KNOWLEDGE_BASE.DELETE')"
                variant="ghost"
                color="ruby"
                @click="deleteQaPair(qa)"
              />
            </div>
          </div>
        </div>
      </div>
    </KBSectionCard>
  </div>
</template>
