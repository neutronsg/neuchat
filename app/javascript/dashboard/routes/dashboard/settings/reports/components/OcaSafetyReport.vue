<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { Chart as ChartJS, Legend } from 'chart.js';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportsAPI from 'dashboard/api/reports';
import Button from 'dashboard/components-next/button/Button.vue';
ChartJS.register(Legend);
const props = defineProps({ filters: { type: Object, required: true } });
const { t } = useI18n();
const data = ref(null);
const loading = ref(false);
const error = ref(false);
const page = ref(1);
const status = ref('');
let generation = 0;
async function load() {
  generation += 1;
  const current = generation;
  loading.value = true;
  error.value = false;
  data.value = null;
  page.value = 1;
  try {
    const response = await ReportsAPI.getBotSafety({ ...props.filters });
    if (current === generation) data.value = response.data;
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.data?.error === 'report_too_large'
          ? 'OCA_REPORT.TOO_LARGE'
          : 'OCA_REPORT.SAFETY.ERROR';
  } finally {
    if (current === generation) loading.value = false;
  }
}
const groups = computed(() => data.value?.groups || []);
const enforcedChecks = computed(() =>
  groups.value.filter(g => g.enforced).reduce((n, g) => n + g.count, 0)
);
const blockedChecks = computed(() =>
  groups.value
    .filter(g => g.enforced && g.status === 'block')
    .reduce((n, g) => n + g.count, 0)
);
const failedChecks = computed(() =>
  groups.value
    .filter(
      g =>
        g.enforced &&
        [
          'error',
          'timeout',
          'indeterminate',
          'unavailable',
          'unsupported',
        ].includes(g.status)
    )
    .reduce((n, g) => n + g.count, 0)
);
const hasShadow = computed(() =>
  data.value?.events.some(e => e.mode === 'aws_shadow')
);
const filtered = computed(() =>
  (data.value?.events || []).filter(
    e => !status.value || e.status === status.value
  )
);
const events = computed(() =>
  filtered.value.slice((page.value - 1) * 20, page.value * 20)
);
const trend = computed(() => {
  const labels = [...new Set(groups.value.map(g => g.day))].sort();
  return {
    labels,
    datasets: [true, false]
      .filter(enforced => enforced || hasShadow.value)
      .map(enforced => ({
        label: t(
          enforced
            ? 'OCA_REPORT.SAFETY.BLOCKED'
            : 'OCA_REPORT.SAFETY.WOULD_BLOCK'
        ),
        backgroundColor: enforced ? '#3182CE' : '#94A3B8',
        data: labels.map(day =>
          groups.value
            .filter(
              g =>
                g.day === day && g.enforced === enforced && g.status === 'block'
            )
            .reduce((n, g) => n + g.count, 0)
        ),
      })),
  };
});
const chartOptions = {
  plugins: { legend: { position: 'bottom' } },
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
const dateTime = at =>
  new Date(at).toLocaleString(undefined, { timeZone: props.filters.timezone });
watch(() => props.filters, load, { immediate: true, deep: true });
watch(status, () => {
  page.value = 1;
});
</script>

<template>
  <section class="rounded-xl border border-n-weak p-6">
    <h3 class="text-lg font-medium">{{ $t('OCA_REPORT.SAFETY.TITLE') }}</h3>
    <p class="mt-1 text-sm text-n-slate-11">
      {{ $t('OCA_REPORT.SAFETY.DESCRIPTION') }}
    </p>
    <p
      v-for="bot in data?.current_modes || []"
      :key="bot.name"
      class="mt-2 text-xs text-n-slate-11"
    >
      {{
        $t('OCA_REPORT.SAFETY.CURRENT_MODE', {
          name: bot.name,
          mode: $t(`OCA_REPORT.SAFETY.MODES.${bot.mode}`),
        })
      }}
    </p>
    <p v-if="loading" class="mt-4 text-sm">
      {{ $t('OCA_REPORT.SAFETY.LOADING') }}
    </p>
    <div v-else-if="error" class="mt-4 flex items-center gap-3">
      <p>{{ $t(error) }}</p>
      <Button
        :label="$t('OCA_REPORT.SAFETY.RETRY')"
        faded
        slate
        @click="load"
      />
    </div>
    <template v-else-if="data">
      <dl class="my-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.CHECKS') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ enforcedChecks }}</dd>
        </div>
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.BLOCKED') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ blockedChecks }}</dd>
        </div>
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.UNKNOWN') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ failedChecks }}</dd>
        </div>
      </dl>
      <div v-if="groups.length" class="mb-6 h-48">
        <BarChart :collection="trend" :chart-options="chartOptions" />
      </div>
      <p v-if="data.reviewerUsage" class="mb-5 text-sm text-n-slate-11">
        {{
          $t('OCA_REPORT.SAFETY.USAGE', {
            input: data.reviewerUsage.inputTokens ?? '—',
            output: data.reviewerUsage.outputTokens ?? '—',
            missing: data.reviewerUsage.missingUsageChecks,
          })
        }}
      </p>
      <div v-if="hasShadow" class="mb-6 rounded-lg bg-n-alpha-2 p-4">
        <h4 class="font-medium">{{ $t('OCA_REPORT.SAFETY.SHADOW') }}</h4>
        <p class="mt-2 text-sm">
          {{ $t('OCA_REPORT.SAFETY.COMPARISON', data.comparison) }}
        </p>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ $t('OCA_REPORT.SAFETY.COMPARISON_NOTE') }}
        </p>
      </div>
      <label for="safety-status" class="text-sm">{{
        $t('OCA_REPORT.SAFETY.RESULT')
      }}</label>
      <select
        id="safety-status"
        v-model="status"
        class="mb-3 ml-2 !w-auto rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
      >
        <option value="">{{ $t('OCA_REPORT.SAFETY.ALL') }}</option>
        <option
          v-for="value in [
            'allow',
            'block',
            'indeterminate',
            'error',
            'timeout',
            'unsupported',
            'skipped',
            'unavailable',
            'masked',
          ]"
          :key="value"
          :value="value"
        >
          {{ $t(`OCA_REPORT.SAFETY.STATUS.${value}`) }}
        </option>
      </select>
      <div v-if="filtered.length" class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-n-weak text-n-slate-11">
            <tr>
              <th
                v-for="key in [
                  'TIME',
                  'CONVERSATION',
                  'PROVIDER',
                  'STAGE',
                  'RESULT',
                  'REASON',
                ]"
                :key="key"
                class="px-2 py-3 font-medium"
              >
                {{ $t(`OCA_REPORT.SAFETY.${key}`) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="event in events"
              :key="`${event.attempt_id}:${event.stage}:${event.provider}`"
              class="border-b border-n-weak"
            >
              <td class="px-2 py-3">{{ dateTime(event.created_at) }}</td>
              <td class="px-2 py-3">#{{ event.conversation_id }}</td>
              <td class="px-2 py-3">
                {{ $t(`OCA_REPORT.SAFETY.PROVIDERS.${event.provider}`) }} ·
                {{
                  $t(
                    event.enforced
                      ? 'OCA_REPORT.SAFETY.ENFORCED'
                      : 'OCA_REPORT.SAFETY.SHADOW_LABEL'
                  )
                }}
              </td>
              <td class="px-2 py-3">
                {{ $t(`OCA_REPORT.SAFETY.STAGES.${event.stage}`) }}
              </td>
              <td class="px-2 py-3">
                {{ $t(`OCA_REPORT.SAFETY.STATUS.${event.status}`) }}
              </td>
              <td class="px-2 py-3">
                {{ $t(`OCA_REPORT.SAFETY.REASONS.${event.reason}`) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!filtered.length" class="py-4 text-sm text-n-slate-11">
        {{ $t('OCA_REPORT.SAFETY.EMPTY') }}
      </p>
      <div v-if="filtered.length > 20" class="mt-4 flex justify-end gap-2">
        <Button
          :label="$t('OCA_REPORT.SAFETY.PREVIOUS')"
          :disabled="page === 1"
          faded
          slate
          @click="page--"
        /><Button
          :label="$t('OCA_REPORT.SAFETY.NEXT')"
          :disabled="page * 20 >= filtered.length"
          faded
          slate
          @click="page++"
        />
      </div>
    </template>
  </section>
</template>
