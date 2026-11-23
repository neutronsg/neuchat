<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { summarizeSafety } from './safetyReport';
import { useI18n } from 'vue-i18n';
import { Chart as ChartJS, Legend } from 'chart.js';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportsAPI from 'dashboard/api/reports';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({ filters: { type: Object, required: true } });
ChartJS.register(Legend);
const { t } = useI18n();
const route = useRoute();
const data = ref(null);
const expanded = ref(new Set());
const toggleRequest = key => {
  const next = new Set(expanded.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  expanded.value = next;
};
const loading = ref(false);
const error = ref(false);
const page = ref(1);
const status = ref('');
const showStatusMenu = ref(false);
const statusItems = computed(() =>
  [
    '',
    'block',
    'error',
    'unavailable',
    'no_block',
    'aws_only',
    'custom_only',
  ].map(value => ({
    action: 'filter',
    value: value || 'all',
    label: value
      ? t(`OCA_REPORT.SAFETY.REQUEST_RESULTS.${value}`)
      : t('OCA_REPORT.SAFETY.ALL'),
    isSelected: value === status.value,
  }))
);
const selectStatus = ({ value }) => {
  status.value = value === 'all' ? '' : value;
  showStatusMenu.value = false;
};
let generation = 0;
async function load() {
  generation += 1;
  const current = generation;
  loading.value = true;
  error.value = false;
  data.value = null;
  page.value = 1;
  expanded.value = new Set();
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
const summary = computed(() => summarizeSafety(data.value?.events));
const requests = computed(() => summary.value.requests);
const blockedRequests = computed(
  () => requests.value.filter(r => r.blocked).length
);
const issueRequests = computed(
  () => requests.value.filter(r => r.reviewFailed || r.incomplete).length
);
const blockRate = computed(() =>
  requests.value.length
    ? `${((blockedRequests.value / requests.value.length) * 100).toFixed(1)}%`
    : '—'
);
const hasShadow = computed(() =>
  requests.value.some(r => r.comparisons.length)
);
const comparisonCards = computed(() =>
  Object.entries(summary.value.comparison)
);
const filtered = computed(() =>
  requests.value.filter(r => {
    if (!status.value) return true;
    if (['aws_only', 'custom_only'].includes(status.value))
      return r.comparisons.includes(status.value);
    if (status.value === 'error') return r.reviewFailed;
    if (status.value === 'unavailable') return r.incomplete;
    return r.result === status.value;
  })
);
const rows = computed(() =>
  filtered.value.slice((page.value - 1) * 20, page.value * 20)
);
const reasonCounts = computed(() => {
  const counts = new Map();
  requests.value.forEach(r =>
    r.reasons.forEach(reason =>
      counts.set(reason, (counts.get(reason) || 0) + 1)
    )
  );
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
});
const trend = computed(() => {
  const days = new Map();
  requests.value.forEach(r => {
    const count = days.get(r.day) || { total: 0, blocked: 0 };
    count.total += 1;
    if (r.blocked) count.blocked += 1;
    days.set(r.day, count);
  });
  const labels = [...days.keys()].sort();
  return {
    labels,
    datasets: [
      {
        label: t('OCA_REPORT.SAFETY.TREND_REQUESTS'),
        backgroundColor: '#3182CE',
        maxBarThickness: 48,
        data: labels.map(day => days.get(day).total),
      },
      {
        label: t('OCA_REPORT.SAFETY.BLOCKED'),
        backgroundColor: '#B7791F',
        maxBarThickness: 48,
        data: labels.map(day => days.get(day).blocked),
      },
    ],
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
      <dl class="my-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.CHECKS') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ requests.length }}</dd>
        </div>
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.BLOCKED') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ blockedRequests }}</dd>
        </div>
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.BLOCK_RATE') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ blockRate }}</dd>
        </div>
        <div>
          <dt class="text-sm text-n-slate-11">
            {{ $t('OCA_REPORT.SAFETY.ISSUES') }}
          </dt>
          <dd class="text-2xl font-semibold">{{ issueRequests }}</dd>
        </div>
      </dl>
      <h4 v-if="requests.length" class="font-medium">
        {{ $t('OCA_REPORT.SAFETY.TREND_TITLE') }}
      </h4>
      <p v-if="requests.length" class="mb-4 mt-1 text-xs text-n-slate-11">
        {{ $t('OCA_REPORT.SAFETY.TREND_NOTE') }}
      </p>
      <div v-if="requests.length" class="mb-6 h-48">
        <BarChart :collection="trend" :chart-options="chartOptions" />
      </div>
      <div
        v-if="reasonCounts.length"
        class="mb-6 rounded-lg border border-n-weak p-4"
      >
        <h4 class="font-medium">{{ $t('OCA_REPORT.SAFETY.REASONS_TITLE') }}</h4>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ $t('OCA_REPORT.SAFETY.REASONS_NOTE') }}
        </p>
        <ul class="mt-3 grid gap-x-8 gap-y-2 sm:grid-cols-2">
          <li
            v-for="[reason, count] in reasonCounts"
            :key="reason"
            class="flex justify-between text-sm"
          >
            <span>{{ $t(`OCA_REPORT.SAFETY.REASONS.${reason}`) }}</span
            ><strong>{{ count }}</strong>
          </li>
        </ul>
      </div>
      <div v-if="hasShadow" class="mb-6 rounded-lg bg-n-alpha-2 p-4">
        <h4 class="font-medium">{{ $t('OCA_REPORT.SAFETY.SHADOW') }}</h4>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ $t('OCA_REPORT.SAFETY.COMPARISON_NOTE') }}
        </p>
        <dl class="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-5">
          <div v-for="[key, count] in comparisonCards" :key="key">
            <dt class="text-xs text-n-slate-11">
              {{ $t(`OCA_REPORT.SAFETY.COMPARISON_RESULTS.${key}`) }}
            </dt>
            <dd class="mt-1 text-xl font-semibold">{{ count }}</dd>
          </div>
        </dl>
      </div>
      <div
        v-if="data.events?.length"
        class="mb-4 flex items-center justify-between gap-3"
      >
        <h4 class="font-medium">{{ $t('OCA_REPORT.SAFETY.DETAILS') }}</h4>
        <div
          v-on-clickaway="() => (showStatusMenu = false)"
          class="relative"
          @keydown.esc="showStatusMenu = false"
        >
          <Button
            sm
            slate
            faded
            trailing-icon="i-lucide-chevron-down"
            :label="
              status
                ? $t(`OCA_REPORT.SAFETY.REQUEST_RESULTS.${status}`)
                : $t('OCA_REPORT.SAFETY.ALL')
            "
            :aria-label="$t('OCA_REPORT.SAFETY.FILTER_RESULT')"
            :aria-expanded="showStatusMenu"
            @click="showStatusMenu = !showStatusMenu"
          />
          <DropdownMenu
            v-if="showStatusMenu"
            :menu-items="statusItems"
            class="right-0 top-full mt-1"
            @action="selectStatus"
          />
        </div>
      </div>
      <div v-if="filtered.length" class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-n-weak text-n-slate-11">
            <tr>
              <th
                v-for="key in [
                  'TIME',
                  'CONVERSATION',
                  'MODE',
                  'AWS',
                  'CUSTOM',
                  'RESULT',
                  'CHECK_DETAILS',
                ]"
                :key="key"
                class="px-2 py-3 font-medium"
              >
                {{ $t(`OCA_REPORT.SAFETY.${key}`) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <template v-for="request in rows" :key="request.key">
              <tr class="border-b border-n-weak align-top">
                <td class="whitespace-nowrap px-2 py-3">
                  {{ dateTime(request.createdAt) }}
                </td>
                <td class="px-2 py-3">
                  <router-link
                    class="text-n-blue-text"
                    :to="`/app/accounts/${route.params.accountId}/conversations/${request.conversationId}`"
                  >
                    #{{ request.conversationId }}
                  </router-link>
                  <span
                    v-if="request.messageId != null"
                    class="block text-xs text-n-slate-11"
                    >{{
                      $t('OCA_REPORT.SAFETY.MESSAGE_ID', {
                        id: request.messageId,
                      })
                    }}</span
                  >
                </td>
                <td class="px-2 py-3">
                  <div v-for="mode in request.modes" :key="mode">
                    {{ $t(`OCA_REPORT.SAFETY.MODES.${mode}`) }}
                  </div>
                </td>
                <td class="px-2 py-3">
                  {{ $t(`OCA_REPORT.SAFETY.STATUS.${request.aws}`) }}
                </td>
                <td class="px-2 py-3">
                  {{ $t(`OCA_REPORT.SAFETY.STATUS.${request.custom}`)
                  }}<span
                    v-if="
                      request.checks.some(
                        check => check.provider === 'custom' && !check.enforced
                      )
                    "
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ $t('OCA_REPORT.SAFETY.SHADOW_ONLY') }}</span
                  >
                </td>
                <td class="px-2 py-3">
                  <span
                    :class="
                      request.blocked ? 'font-medium text-n-amber-11' : ''
                    "
                    >{{
                      $t(`OCA_REPORT.SAFETY.REQUEST_RESULTS.${request.result}`)
                    }}</span
                  >
                  <span
                    v-if="request.shadowMissing"
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ $t('OCA_REPORT.SAFETY.SHADOW_MISSING') }}</span
                  >
                  <span
                    v-if="request.reviewFailed && !request.failed"
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ $t('OCA_REPORT.SAFETY.SHADOW_FAILURE') }}</span
                  >
                  <span
                    v-for="reason in request.reasons"
                    :key="reason"
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ $t(`OCA_REPORT.SAFETY.REASONS.${reason}`) }}</span
                  >
                </td>
                <td class="px-2 py-3">
                  <Button
                    sm
                    slate
                    faded
                    :aria-expanded="expanded.has(request.key)"
                    :label="
                      $t(
                        expanded.has(request.key)
                          ? 'OCA_REPORT.SAFETY.HIDE_CHECKS'
                          : 'OCA_REPORT.SAFETY.SHOW_CHECKS',
                        { count: request.checks.length }
                      )
                    "
                    @click="toggleRequest(request.key)"
                  />
                </td>
              </tr>
              <tr v-if="expanded.has(request.key)" class="bg-n-alpha-2">
                <td colspan="7" class="p-4">
                  <p class="mb-3 text-xs text-n-slate-11">
                    {{ $t('OCA_REPORT.SAFETY.EVIDENCE_NOTE') }}
                  </p>
                  <ol class="space-y-3">
                    <li
                      v-for="check in request.checks"
                      :key="`${check.attempt_id}:${check.stage}:${check.provider}`"
                      class="flex flex-wrap gap-x-3 gap-y-1 text-xs"
                    >
                      <span>{{ dateTime(check.created_at) }}</span>
                      <strong>{{
                        $t(`OCA_REPORT.SAFETY.PROVIDERS.${check.provider}`)
                      }}</strong>
                      <span>{{
                        $t(`OCA_REPORT.SAFETY.STAGES.${check.stage}`)
                      }}</span>
                      <span>{{
                        $t(
                          check.enforced
                            ? 'OCA_REPORT.SAFETY.ENFORCED'
                            : 'OCA_REPORT.SAFETY.SHADOW_LABEL'
                        )
                      }}</span>
                      <span>{{
                        $t(
                          `OCA_REPORT.SAFETY.STATUS.${check.notRequired ? 'not_required' : check.status}`
                        )
                      }}</span>
                      <span>{{
                        $t(`OCA_REPORT.SAFETY.REASONS.${check.reason}`)
                      }}</span>
                      <span class="basis-full break-all text-n-slate-11">{{
                        $t('OCA_REPORT.SAFETY.ATTEMPT', {
                          id: check.attempt_id,
                          version: check.policy_version || '—',
                        })
                      }}</span>
                    </li>
                  </ol>
                </td>
              </tr>
            </template>
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
      <details class="mt-6 text-sm text-n-slate-11">
        <summary class="cursor-pointer">
          {{ $t('OCA_REPORT.SAFETY.TECHNICAL') }}
        </summary>
        <p class="mt-2">{{ $t('OCA_REPORT.SAFETY.COUNTING_NOTE') }}</p>
        <p v-if="data.reviewerUsage" class="mt-2">
          {{
            $t('OCA_REPORT.SAFETY.USAGE', {
              input: data.reviewerUsage.inputTokens ?? '—',
              output: data.reviewerUsage.outputTokens ?? '—',
              missing: data.reviewerUsage.missingUsageChecks,
            })
          }}
        </p>
      </details>
    </template>
  </section>
</template>
