<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import OcaCostEstimate from './OcaCostEstimate.vue';
import OcaCategoryBreakdown from './OcaCategoryBreakdown.vue';
import OcaEscalationDetails from './OcaEscalationDetails.vue';
import { useRoute } from 'vue-router';
import ReportsAPI from 'dashboard/api/reports';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportMetricCard from './ReportMetricCard.vue';
import { downloadReport, reportFilename } from './reportDownload';
const props = defineProps({ filters: { type: Object, required: true } });
const route = useRoute();
const { t } = useI18n();
const metrics = ref(null);
const metricsError = ref(false);
const metricsTooLarge = ref(false);
const usageLoading = ref(false);
const report = ref(null);
const usage = ref(null);
const error = ref(false);
const usageError = ref(false);
const loading = ref(false);
const page = ref(1);
const reason = ref('');
const dateTime = value =>
  value
    ? new Date(value).toLocaleString('en-SG', {
        timeZone: props.filters.timezone,
      })
    : '—';
let generation = 0;
let usageGeneration = 0;
const number = value =>
  value === null || value === undefined
    ? '—'
    : Number(value).toLocaleString(undefined, { maximumFractionDigits: 6 });
const rate = value =>
  value === null || value === undefined ? '—' : `${(value * 100).toFixed(1)}%`;
const chart = (labels, values, label) => ({
  labels,
  datasets: [{ label, data: values, backgroundColor: '#2f86eb' }],
});
const resolutionChart = computed(() =>
  chart(
    report.value?.days.map(d => d.day) || [],
    report.value?.days.map(d => d.resolutions) || [],
    t('OCA_REPORT.RESOLUTION_COUNT')
  )
);
const escalationChart = computed(() =>
  chart(
    report.value?.days.map(d => d.day) || [],
    report.value?.days.map(d => d.escalations) || [],
    t('OCA_REPORT.ESCALATION_COUNT')
  )
);
const tokenChart = computed(() =>
  chart(
    usage.value?.days.map(d => d.group) || [],
    usage.value?.days.map(d =>
      d.inputTokens === null || d.outputTokens === null
        ? null
        : d.inputTokens + d.outputTokens
    ) || [],
    t('OCA_REPORT.TOKENS')
  )
);
async function fetchReport() {
  if (!props.filters.from || !props.filters.to) return;
  generation += 1;
  const current = generation;
  loading.value = true;
  error.value = false;
  try {
    const response = await ReportsAPI.getBotOutcomes({
      ...props.filters,
      page: page.value,
      reason: reason.value,
    });
    if (current === generation) report.value = response.data;
  } catch (failure) {
    if (current === generation) {
      error.value =
        failure.response?.data?.error === 'report_too_large'
          ? 'OCA_REPORT.TOO_LARGE'
          : 'OCA_REPORT.ERROR';
      report.value = null;
    }
  } finally {
    if (current === generation) loading.value = false;
  }
}
async function fetchUsage() {
  usageGeneration += 1;
  const current = usageGeneration;
  usageLoading.value = true;
  usage.value = null;
  usageError.value = false;
  const filters = { ...props.filters };
  try {
    const response = await ReportsAPI.getBotUsage(filters);
    if (current === usageGeneration) usage.value = response.data;
  } catch (failure) {
    if (current === usageGeneration)
      usageError.value =
        failure.response?.data?.error === 'report_too_large'
          ? 'OCA_REPORT.TOO_LARGE'
          : 'OCA_REPORT.USAGE_ERROR';
  } finally {
    if (current === usageGeneration) usageLoading.value = false;
  }
}
function exportUsage() {
  const keys = [
    'group',
    'timezone',
    'calls',
    'inputTokens',
    'outputTokens',
    'cacheReadTokens',
    'cacheWriteTokens',
    'cacheHitRate',
    'estimatedCostUsd',
    'estimatedGuardrailCostUsd',
    'estimatedCombinedCostUsd',
    'unpricedGuardrailCalls',
    'usageMissingCalls',
    'unpricedCalls',
  ];
  downloadReport(
    [
      keys.join(','),
      ...usage.value.days.map(d =>
        keys
          .map(k => (k === 'timezone' ? usage.value.timezone : (d[k] ?? '')))
          .join(',')
      ),
    ].join('\r\n'),
    reportFilename('usage', props.filters, 'csv')
  );
}
let metricsGeneration = 0;
async function fetchMetrics() {
  metricsGeneration += 1;
  const current = metricsGeneration;
  metricsError.value = false;
  metricsTooLarge.value = false;
  metrics.value = null;
  try {
    const response = await ReportsAPI.getBotMetrics(props.filters);
    if (current === metricsGeneration) metrics.value = response.data;
  } catch (failure) {
    if (current === metricsGeneration) {
      metricsError.value = true;
      metricsTooLarge.value =
        failure.response?.data?.error === 'report_too_large';
    }
  }
}
function setReason(value) {
  reason.value = value;
  page.value = 1;
}
function setPage(value) {
  page.value = value;
}
watch(
  () => [
    props.filters.from,
    props.filters.to,
    props.filters.timezone,
    page.value,
    reason.value,
  ],
  fetchReport,
  { immediate: true }
);
watch(
  () => [props.filters.from, props.filters.to, props.filters.timezone],
  () => {
    page.value = 1;
    report.value = null;
    if (props.filters.from && props.filters.to) {
      fetchUsage();
      fetchMetrics();
    }
  },
  { immediate: true }
);
const chartOptions = {
  plugins: { legend: { display: false } },
  scales: {
    x: {
      grid: { display: false },
      ticks: { maxRotation: 0, maxTicksLimit: 6 },
    },
    y: {
      beginAtZero: true,
      ticks: { precision: 0 },
      grid: { color: 'rgba(128,128,128,0.12)' },
    },
  },
};
const usageStats = computed(() => [
  { key: 'INPUT', value: number(usage.value?.total?.inputTokens) },
  { key: 'OUTPUT', value: number(usage.value?.total?.outputTokens) },
  { key: 'CACHE_READ', value: number(usage.value?.total?.cacheReadTokens) },
  { key: 'CACHE_WRITE', value: number(usage.value?.total?.cacheWriteTokens) },
  { key: 'CACHE', value: rate(usage.value?.total?.cacheHitRate) },
]);
</script>

<template>
  <div class="flex min-w-0 flex-col gap-6 pb-8">
    <div
      v-if="error"
      role="alert"
      class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
    >
      {{ $t(error) }}
      <Button
        variant="outline"
        size="sm"
        color="slate"
        :label="$t('OCA_REPORT.RETRY')"
        @click="fetchReport"
      />
    </div>
    <p
      v-if="loading && !report"
      role="status"
      class="py-10 text-center text-sm text-n-slate-11"
    >
      {{ $t('OCA_REPORT.LOADING') }}
    </p>
    <template v-if="report">
      <div
        class="grid grid-cols-1 gap-x-6 sm:grid-cols-2 gap-y-5 rounded-xl border border-n-weak bg-n-solid-2 p-5 sm:p-6 xl:grid-cols-4"
      >
        <ReportMetricCard
          :label="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.LABEL')"
          :info-text="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.TOOLTIP')"
          :value="number(metrics?.conversation_count)"
        />
        <ReportMetricCard
          :label="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
          :info-text="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
          :value="number(metrics?.message_count)"
        />
        <ReportMetricCard
          :label="$t('OCA_REPORT.RESOLUTION')"
          :info-text="$t('OCA_REPORT.RESOLUTION_INFO')"
          :value="`${report.resolution_rate}%`"
        />
        <ReportMetricCard
          :label="$t('OCA_REPORT.ESCALATION')"
          :info-text="$t('OCA_REPORT.ESCALATION_INFO')"
          :value="`${report.escalation_rate}%`"
        />
      </div>
      <div
        v-if="metricsError"
        role="alert"
        class="flex items-center gap-3 text-sm text-n-slate-11"
      >
        {{
          metricsTooLarge
            ? $t('OCA_REPORT.TOO_LARGE')
            : $t('OCA_REPORT.METRICS_ERROR')
        }}<Button
          size="sm"
          variant="ghost"
          :label="$t('OCA_REPORT.RETRY')"
          @click="fetchMetrics"
        />
      </div>
      <details class="-mt-3 text-xs text-n-slate-11">
        <summary
          class="w-fit cursor-pointer rounded py-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ $t('OCA_REPORT.ABOUT') }}
        </summary>
        <p class="mb-0 mt-2 max-w-prose leading-5">
          {{ $t('OCA_REPORT.COHORT') }}
          {{ dateTime(report.tracking_started_at) }}
        </p>
      </details>
      <div class="grid min-w-0 grid-cols-1 gap-6 lg:grid-cols-2">
        <section
          v-for="item in [
            { key: 'RESOLUTION_COUNT', data: resolutionChart },
            { key: 'ESCALATION_COUNT', data: escalationChart },
          ]"
          :key="item.key"
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-5 sm:p-6"
        >
          <h2 class="mb-5 mt-0 text-base font-medium text-n-slate-12">
            {{ $t(`OCA_REPORT.${item.key}`) }}
          </h2>
          <div v-if="report.conversation_count" class="h-48">
            <BarChart :collection="item.data" :chart-options="chartOptions" />
          </div>
          <p
            v-else
            class="flex h-48 items-center justify-center text-sm text-n-slate-11"
          >
            {{ $t('OCA_REPORT.NO_CONVERSATIONS') }}
          </p>
        </section>
      </div>
      <div class="grid min-w-0 grid-cols-1 items-start gap-6 xl:grid-cols-2">
        <OcaCategoryBreakdown
          :categories="report.categories"
          :account-id="route.params.accountId"
        />
        <section
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-5 sm:p-6"
          aria-labelledby="usage-heading"
        >
          <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
            <h2
              id="usage-heading"
              class="m-0 text-base font-medium text-n-slate-12"
            >
              {{ $t('OCA_REPORT.TOKENS') }}
            </h2>
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-download"
              :disabled="!usage?.days?.length || usageLoading"
              :label="$t('OCA_REPORT.DOWNLOAD_USAGE')"
              @click="exportUsage"
            />
          </div>
          <p
            v-if="usageLoading"
            role="status"
            class="py-10 text-center text-sm text-n-slate-11"
          >
            {{ $t('OCA_REPORT.LOADING') }}
          </p>
          <div
            v-else-if="usageError"
            role="alert"
            class="flex flex-col items-start gap-3 py-6 text-sm text-n-slate-11"
          >
            {{ $t(usageError)
            }}<Button
              variant="outline"
              color="slate"
              size="sm"
              :label="$t('OCA_REPORT.RETRY')"
              @click="fetchUsage"
            />
          </div>
          <template v-else-if="usage">
            <div v-if="usage.days.length" class="mb-6 h-40">
              <BarChart
                :collection="tokenChart"
                :chart-options="chartOptions"
              />
            </div>
            <p v-else class="py-6 text-center text-sm text-n-slate-11">
              {{ $t('OCA_REPORT.NO_USAGE') }}
            </p>
            <dl
              class="m-0 grid grid-cols-1 gap-x-5 sm:grid-cols-2 gap-y-5 border-t border-n-weak pt-5"
            >
              <div v-for="stat in usageStats" :key="stat.key">
                <dt class="text-xs text-n-slate-11">
                  {{ $t(`OCA_REPORT.${stat.key}`) }}
                </dt>
                <dd
                  class="m-0 mt-1 text-lg font-medium tabular-nums text-n-slate-12"
                >
                  {{ stat.value }}
                  <span
                    v-if="
                      (stat.key === 'COST' && usage.total?.unpricedCalls > 0) ||
                      (stat.key === 'GUARDRAIL_COST' &&
                        usage.total?.unpricedGuardrailCalls > 0) ||
                      (stat.key === 'COMBINED_COST' &&
                        (usage.total?.unpricedCalls > 0 ||
                          usage.total?.unpricedGuardrailCalls > 0))
                    "
                    class="mt-1 block text-xs font-normal text-n-slate-11"
                  >
                    {{ $t('OCA_REPORT.PARTIAL_COST') }}
                  </span>
                </dd>
              </div>
            </dl>
            <p class="mt-4 text-xs text-n-slate-11">
              {{ $t('OCA_REPORT.MISSING_USAGE') }}
              {{ number(usage.total?.usageMissingCalls) }}
            </p>
          </template>
        </section>
      </div>
      <OcaCostEstimate
        :usage="usage"
        :loading="usageLoading"
        :error="!!usageError"
        @retry="fetchUsage"
      />
      <OcaEscalationDetails
        :report="report"
        :loading="loading"
        :reason="reason"
        :page="page"
        :account-id="route.params.accountId"
        @filter="setReason"
        @page="setPage"
      />
    </template>
  </div>
</template>
