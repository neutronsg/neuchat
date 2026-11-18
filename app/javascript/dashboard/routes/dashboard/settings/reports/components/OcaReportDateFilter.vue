<script setup>
import { ref, onMounted } from 'vue';
import WootDateRangePicker from 'dashboard/components/ui/DateRangePicker.vue';
import ReportsFiltersDateRange from './Filters/DateRange.vue';
import {
  singaporeRange,
  singaporeToday,
  singaporePreset,
  MAX_REPORT_DAYS,
} from './ocaReportDates';

const emit = defineEmits(['filterChange']);
const custom = ref(false);
const dates = ref([singaporeToday(), singaporeToday()]);
const error = ref(false);
const publishCustom = value => {
  dates.value = value;
  try {
    const range = singaporeRange(value);
    error.value = false;
    emit('filterChange', range);
  } catch {
    error.value = true;
  }
};
const changePreset = option => {
  custom.value = option.offset === null;
  error.value = false;
  if (custom.value) publishCustom(dates.value);
  else emit('filterChange', singaporePreset(option.offset));
};
onMounted(() => emit('filterChange', singaporePreset(6)));
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap gap-2">
      <ReportsFiltersDateRange
        :max-days="MAX_REPORT_DAYS"
        @on-range-change="changePreset"
      />
      <WootDateRangePicker
        v-if="custom"
        :value="dates"
        :confirm-text="$t('REPORT.CUSTOM_DATE_RANGE.CONFIRM')"
        :placeholder="$t('REPORT.CUSTOM_DATE_RANGE.PLACEHOLDER')"
        @change="publishCustom"
      />
    </div>
    <p class="m-0 text-sm text-n-slate-11">{{ $t('OCA_REPORT.DATE_HELP') }}</p>
    <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ $t('OCA_REPORT.DATE_ERROR') }}
    </p>
  </div>
</template>
