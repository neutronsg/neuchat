<script setup>
import { ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ReportsAPI from 'dashboard/api/reports';
import { downloadReport, reportFilename } from './reportDownload';
const props = defineProps({ filters: { type: Object, required: true } });
const exporting = ref(false);
const error = ref(false);
let generation = 0;
watch(
  () => [props.filters.from, props.filters.to, props.filters.timezone],
  () => {
    generation += 1;
    error.value = false;
  }
);
async function download() {
  if (exporting.value) return;
  const current = generation;
  const filters = { ...props.filters };
  exporting.value = true;
  error.value = false;
  try {
    const response = await ReportsAPI.getBotWorkbook(filters);
    if (current !== generation) return;
    downloadReport(
      response.data,
      reportFilename('bot', filters, 'xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
  } catch (failure) {
    let code = failure.response?.data?.error;
    if (failure.response?.data instanceof Blob) {
      try {
        code = JSON.parse(await failure.response.data.text()).error;
      } catch {
        /* Keep the generic error for unreadable responses. */
      }
    }
    if (current === generation)
      error.value =
        code === 'report_too_large'
          ? 'OCA_REPORT.TOO_LARGE'
          : 'OCA_REPORT.EXPORT_ERROR';
  } finally {
    exporting.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col items-end gap-2">
    <Button
      variant="solid"
      color="blue"
      size="sm"
      icon="i-lucide-download"
      :label="$t('OCA_REPORT.DOWNLOAD')"
      :is-loading="exporting"
      :disabled="!filters.from || !filters.to || exporting"
      @click="download"
    />
    <p v-if="error" role="alert" class="m-0 max-w-xs text-sm text-n-ruby-11">
      {{ $t(error) }}
    </p>
  </div>
</template>
