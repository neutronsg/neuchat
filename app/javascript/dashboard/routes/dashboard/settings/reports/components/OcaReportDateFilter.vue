<script setup>
import { ref, onMounted } from 'vue';
import DatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { browserRange, browserPreset } from './ocaReportDates';

const emit = defineEmits(['filterChange']);
const error = ref(false);
const publish = dates => {
  try {
    const range = browserRange(dates);
    error.value = false;
    emit('filterChange', range);
  } catch {
    error.value = true;
  }
};
onMounted(() => emit('filterChange', browserPreset(6)));
</script>

<template>
  <div class="flex flex-col gap-2">
    <DatePicker @date-range-changed="publish" />
    <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ $t('OCA_REPORT.DATE_ERROR') }}
    </p>
  </div>
</template>
