<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

defineProps({
  disabled: {
    type: Boolean,
    default: false,
  },
  showReset: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['reset']);

const model = defineModel('modelValue', {
  type: Object,
  required: true,
});

const updateField = (field, value) => {
  model.value = {
    ...model.value,
    [field]: value,
  };
};

const updateRule = (field, value) => {
  model.value = {
    ...model.value,
    preProcessingRules: {
      ...model.value.preProcessingRules,
      [field]: value,
    },
  };
};
</script>

<template>
  <div class="rounded-xl border border-n-weak bg-n-background p-5">
    <div class="mb-5 flex items-center justify-between gap-3">
      <h4 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('KNOWLEDGE_BASE.CHUNK_SETTINGS_TITLE') }}
      </h4>
      <Button
        v-if="showReset"
        :label="$t('KNOWLEDGE_BASE.CHUNK_SETTINGS_RESET')"
        variant="link"
        color="slate"
        type="button"
        :disabled="disabled"
        @click="emit('reset')"
      />
    </div>

    <div class="flex flex-col gap-4">
      <Input
        :model-value="model.separator"
        :label="$t('KNOWLEDGE_BASE.CHUNK_SETTINGS_FIELDS.DELIMITER')"
        :disabled="disabled"
        @update:model-value="updateField('separator', $event)"
      />

      <Input
        :model-value="model.maxTokens"
        type="number"
        min="1"
        :label="$t('KNOWLEDGE_BASE.CHUNK_SETTINGS_FIELDS.MAX_TOKENS')"
        :disabled="disabled"
        @update:model-value="updateField('maxTokens', $event)"
      />

      <Input
        :model-value="model.chunkOverlap"
        type="number"
        min="0"
        :label="$t('KNOWLEDGE_BASE.CHUNK_SETTINGS_FIELDS.CHUNK_OVERLAP')"
        :disabled="disabled"
        @update:model-value="updateField('chunkOverlap', $event)"
      />

      <label class="flex items-center gap-3 text-sm text-n-slate-12">
        <Checkbox
          :model-value="model.preProcessingRules.removeExtraSpaces"
          :disabled="disabled"
          @update:model-value="updateRule('removeExtraSpaces', $event)"
        />
        <span>{{
          $t('KNOWLEDGE_BASE.CHUNK_SETTINGS_FIELDS.REMOVE_EXTRA_SPACES')
        }}</span>
      </label>

      <label class="flex items-center gap-3 text-sm text-n-slate-12">
        <Checkbox
          :model-value="model.preProcessingRules.removeUrlsEmails"
          :disabled="disabled"
          @update:model-value="updateRule('removeUrlsEmails', $event)"
        />
        <span>{{
          $t('KNOWLEDGE_BASE.CHUNK_SETTINGS_FIELDS.REMOVE_URLS_EMAILS')
        }}</span>
      </label>
    </div>
  </div>
</template>
