<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/botSafetyReviews';
import Button from 'dashboard/components-next/button/Button.vue';
const { t } = useI18n();
const runs = ref([]);
const profiles = ref([]);
const from = ref(new Date().toLocaleDateString('en-CA'));
const to = ref(from.value);
const profile = ref('');
const scope = ref('all');
const maxRequests = ref(100);
const maxCalls = ref(0);
const busy = ref(false);
const error = ref(false);
const selected = ref(null);
const items = ref([]);
const note = ref('');
const verdict = ref('observing');
const itemId = ref(null);
const findingsOnly = ref(false);
const labels = new Set([
  'queued',
  'running',
  'completed',
  'incomplete',
  'failed',
  'pending',
  'insufficient_evidence',
  'execution_error',
  'budget_exhausted',
  'no_issue',
  'possible_false_positive',
  'possible_false_negative',
  'outside_filter',
  'export_only',
  'observing',
  'correct',
  'false_positive',
  'false_negative',
]);
const display = value =>
  labels.has(value)
    ? t(`OCA_REPORT.REVIEW.LABELS.${value}`)
    : (value || '').replaceAll('_', ' ');
const countsText = counts =>
  Object.entries(counts)
    .map(([state, count]) => `${display(state)}: ${count}`)
    .join(' · ');
const batchRange = settings => {
  const format = value =>
    new Date(value).toLocaleDateString('en-GB', {
      timeZone: settings.timezone,
    });
  return `${format(settings.from)} – ${format(new Date(settings.to).getTime() - 1)}`;
};
let key = null;
let previousSettings = '';
async function perform(operation) {
  if (busy.value) return;
  busy.value = true;
  error.value = false;
  try {
    await operation();
  } catch {
    error.value = true;
  } finally {
    busy.value = false;
  }
}
async function refresh() {
  runs.value = (await API.get()).data;
}
async function create() {
  await perform(async () => {
    const settings = {
      from_date: from.value,
      to_date: to.value,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      profile: profile.value,
      scope: scope.value,
      max_requests: Number(maxRequests.value),
      max_calls: Number(maxCalls.value),
      dry_run: !profile.value,
    };
    const serialized = JSON.stringify(settings);
    if (!key || previousSettings !== serialized) key = crypto.randomUUID();
    previousSettings = serialized;
    await API.create({ ...settings, idempotency_key: key });
    key = null;
    await refresh();
  });
}
async function inspect(run, more = false) {
  await perform(async () => {
    const response = await API.items(
      run.id,
      more ? items.value.at(-1)?.id : 0,
      findingsOnly.value
    );
    selected.value = run;
    if (!more) {
      itemId.value = null;
      note.value = '';
    }
    items.value = more
      ? [...items.value, ...response.data.items]
      : response.data.items;
  });
}
async function action(run, name) {
  await perform(async () => {
    await API.action(run.id, name);
    await refresh();
  });
}
async function download(run) {
  await perform(async () => {
    const response = await API.download(run.id);
    const url = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `safety-review-${run.id}.zip`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
}
async function annotate() {
  await perform(async () => {
    await API.action(selected.value.id, 'annotate', {
      item_id: itemId.value,
      verdict: verdict.value,
      review_note: note.value,
    });
    note.value = '';
    itemId.value = null;
    items.value = (
      await API.items(selected.value.id, 0, findingsOnly.value)
    ).data.items;
  });
}
onMounted(() =>
  perform(async () => {
    await refresh();
    profiles.value = (await API.profiles()).data.profiles;
  })
);
</script>

<template>
  <details class="mt-6 border-t border-n-weak pt-6">
    <summary class="cursor-pointer font-medium">
      {{ t('OCA_REPORT.REVIEW.TITLE') }}
    </summary>
    <div class="flex items-center justify-end gap-3">
      <Button
        :label="t('OCA_REPORT.REVIEW.REFRESH')"
        variant="ghost"
        color="slate"
        size="sm"
        :disabled="busy"
        @click="perform(refresh)"
      />
    </div>
    <p class="mt-2 text-sm text-n-slate-11">
      {{ t('OCA_REPORT.REVIEW.DESCRIPTION') }}
    </p>
    <form
      class="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3"
      @submit.prevent="create"
    >
      <label class="text-sm">
        <span class="mb-1 block">{{ t('OCA_REPORT.REVIEW.FROM') }}</span>
        <input v-model="from" name="review-from" type="date" required />
      </label>
      <label class="text-sm">
        <span class="mb-1 block">{{ t('OCA_REPORT.REVIEW.TO') }}</span>
        <input v-model="to" name="review-to" type="date" required />
      </label>
      <label
        >{{ t('OCA_REPORT.REVIEW.SCOPE')
        }}<select v-model="scope">
          <option
            v-for="s in ['all', 'blocked', 'allowed', 'issues']"
            :key="s"
            :value="s"
          >
            {{ t(`OCA_REPORT.REVIEW.SCOPES.${s}`) }}
          </option>
        </select></label
      >
      <label
        >{{ t('OCA_REPORT.REVIEW.PROFILE')
        }}<select v-model="profile">
          <option value="">{{ t('OCA_REPORT.REVIEW.EXPORT_ONLY') }}</option>
          <option v-for="p in profiles" :key="p.name" :value="p.name">
            {{ p.name }} — {{ p.model }}
          </option>
        </select></label
      >
      <label
        >{{ t('OCA_REPORT.REVIEW.REQUESTS')
        }}<input
          v-model="maxRequests"
          type="number"
          min="1"
          max="10000"
          required
      /></label>
      <label
        >{{ t('OCA_REPORT.REVIEW.CALLS')
        }}<input
          v-model="maxCalls"
          type="number"
          min="0"
          :max="maxRequests"
          required
      /></label>
      <div>
        <Button
          type="submit"
          :label="t('OCA_REPORT.REVIEW.CREATE')"
          :disabled="busy"
        />
      </div>
    </form>
    <p v-if="error" role="alert" class="mt-3 text-n-ruby-11">
      {{ t('OCA_REPORT.REVIEW.ERROR') }}
    </p>
    <div class="mt-4 overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead>
          <tr>
            <th>{{ t('OCA_REPORT.REVIEW.BATCH') }}</th>
            <th>{{ t('OCA_REPORT.REVIEW.STATUS') }}</th>
            <th>{{ t('OCA_REPORT.REVIEW.CALLS') }}</th>
            <th>{{ t('OCA_REPORT.REVIEW.ACTIONS') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="run in runs" :key="run.id" class="border-t border-n-weak">
            <td class="py-3">
              #{{ run.id }}
              <div class="text-xs text-n-slate-11">
                {{ batchRange(run.settings) }} · {{ run.settings.timezone }}
              </div>
            </td>
            <td>
              <p v-if="run.export_status === 'failed'" class="text-n-ruby-11">
                {{ t('OCA_REPORT.REVIEW.EXPORT_FAILED') }}
              </p>
              {{ display(run.status) }}
              <div class="text-xs text-n-slate-11">
                {{ countsText(run.counts) }}
              </div>
            </td>
            <td>{{ run.calls_reserved }} / {{ run.settings.max_calls }}</td>
            <td>
              <div class="flex flex-wrap gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  :label="t('OCA_REPORT.REVIEW.RESULTS')"
                  :disabled="busy"
                  @click="inspect(run)"
                />
                <Button
                  v-if="run.can_resume"
                  variant="ghost"
                  size="sm"
                  :label="t('OCA_REPORT.REVIEW.RESUME')"
                  :disabled="busy"
                  @click="action(run, 'resume')"
                />
                <Button
                  v-if="
                    ['completed', 'incomplete', 'failed'].includes(run.status)
                  "
                  variant="ghost"
                  size="sm"
                  :label="t('OCA_REPORT.REVIEW.EXPORT')"
                  :disabled="busy"
                  @click="action(run, 'export')"
                />
                <Button
                  v-if="run.export_ready"
                  variant="ghost"
                  size="sm"
                  :label="t('OCA_REPORT.REVIEW.DOWNLOAD')"
                  :disabled="busy"
                  @click="download(run)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="!runs.length && !busy" class="py-4 text-n-slate-11">
        {{ t('OCA_REPORT.REVIEW.EMPTY') }}
      </p>
    </div>
    <div v-if="selected" class="mt-4 rounded-lg border border-n-weak p-4">
      <h4>{{ t('OCA_REPORT.REVIEW.RESULTS') }} #{{ selected.id }}</h4>
      <label class="mt-3 flex items-center gap-2 text-sm">
        <input
          v-model="findingsOnly"
          type="checkbox"
          :disabled="busy"
          @change="inspect(selected)"
        />
        {{ t('OCA_REPORT.REVIEW.FINDINGS_ONLY') }}
      </label>
      <div
        v-for="item in items"
        :key="item.id"
        class="border-b border-n-weak py-3 text-sm"
      >
        <div>
          #{{ item.message_id }} ·
          {{
            display(
              item.result.result?.verdict || item.result.outcome || item.status
            )
          }}
        </div>
        <p>
          {{
            item.result.result?.reason ||
            item.result.reason ||
            item.result.error
          }}
        </p>
        <p v-for="(n, index) in item.notes" :key="index">
          {{ display(n.verdict) }}: {{ n.note }}
        </p>
        <Button
          variant="ghost"
          size="sm"
          :label="t('OCA_REPORT.REVIEW.ANNOTATE')"
          :disabled="busy"
          @click="itemId = item.id"
        />
      </div>
      <Button
        v-if="items.length && items.length % 50 === 0"
        variant="ghost"
        size="sm"
        :label="t('OCA_REPORT.REVIEW.MORE')"
        :disabled="busy"
        @click="inspect(selected, true)"
      />
      <form v-if="itemId" class="mt-3" @submit.prevent="annotate">
        <label
          >{{ t('OCA_REPORT.REVIEW.VERDICT')
          }}<select v-model="verdict">
            <option
              v-for="v in [
                'correct',
                'false_positive',
                'false_negative',
                'insufficient_evidence',
                'observing',
              ]"
              :key="v"
              :value="v"
            >
              {{ t(`OCA_REPORT.REVIEW.VERDICTS.${v}`) }}
            </option>
          </select></label
        >
        <label
          >{{ t('OCA_REPORT.REVIEW.NOTE')
          }}<textarea v-model="note" maxlength="4000" required />
        </label>
        <Button
          type="submit"
          :label="t('OCA_REPORT.REVIEW.SAVE')"
          :disabled="busy"
        />
      </form>
    </div>
  </details>
</template>
