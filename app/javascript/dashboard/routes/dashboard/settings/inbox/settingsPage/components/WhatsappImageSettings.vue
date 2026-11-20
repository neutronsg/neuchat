<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const store = useStore();
const { t } = useI18n();
const enabled = ref(false);
const reply = ref('');
const saving = ref(false);
const replyLength = computed(() => [...reply.value].length);
const replyInvalid = computed(
  () => !reply.value.trim() || replyLength.value > 1000
);
const changed = computed(
  () =>
    enabled.value !== (props.inbox.image_messages_enabled === true) ||
    reply.value !== props.inbox.image_unavailable_message
);
watch(
  () => [
    props.inbox.id,
    props.inbox.image_messages_enabled,
    props.inbox.image_unavailable_message,
  ],
  () => {
    enabled.value = props.inbox.image_messages_enabled === true;
    reply.value =
      props.inbox.image_unavailable_message ??
      props.inbox.default_image_unavailable_message ??
      '';
  },
  { immediate: true }
);

const save = async () => {
  if (saving.value || !changed.value || replyInvalid.value) return;
  saving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        image_messages_enabled: enabled.value,
        image_unavailable_message: reply.value,
      },
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SettingsSection
    :title="t('INBOX_MGMT.WHATSAPP_IMAGES.TITLE')"
    :sub-title="t('INBOX_MGMT.WHATSAPP_IMAGES.DESCRIPTION')"
  >
    <form class="flex flex-col gap-5" @submit.prevent="save">
      <div class="flex items-center gap-3 min-h-8">
        <button
          :id="`image-switch-${inbox.id}`"
          type="button"
          role="switch"
          :aria-checked="enabled"
          :aria-label="t('INBOX_MGMT.WHATSAPP_IMAGES.LABEL')"
          :disabled="saving"
          class="flex items-center justify-center w-11 h-11 !p-0 shrink-0 rounded-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:opacity-50"
          @click="enabled = !enabled"
        >
          <span
            class="relative block w-9 h-5 shrink-0 rounded-full transition-colors motion-reduce:transition-none"
            :class="enabled ? 'bg-n-brand' : 'bg-n-slate-6'"
            aria-hidden="true"
          >
            <span
              class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-transform motion-reduce:transition-none"
              :class="enabled ? 'translate-x-4' : 'translate-x-0'"
            />
          </span>
        </button>
        <label
          :for="`image-switch-${inbox.id}`"
          class="mb-0 text-sm font-medium cursor-pointer"
        >
          {{ t('INBOX_MGMT.WHATSAPP_IMAGES.LABEL') }}
        </label>
      </div>
      <div :id="`image-reply-fields-${inbox.id}`" class="flex flex-col gap-2">
        <div
          class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1"
        >
          <label
            :for="`image-reply-${inbox.id}`"
            class="mb-0 text-sm font-medium"
          >
            {{ t('INBOX_MGMT.WHATSAPP_IMAGES.REPLY_LABEL') }}
          </label>
          <Button
            type="button"
            variant="link"
            size="sm"
            :disabled="
              saving || reply === inbox.default_image_unavailable_message
            "
            @click="reply = inbox.default_image_unavailable_message"
          >
            {{ t('INBOX_MGMT.WHATSAPP_IMAGES.RESET') }}
          </Button>
        </div>
        <textarea
          :id="`image-reply-${inbox.id}`"
          v-model="reply"
          rows="4"
          class="!mb-0 !min-h-28 text-sm leading-6 resize-y"
          :disabled="saving"
          :aria-invalid="replyInvalid"
          :aria-describedby="`image-reply-help-${inbox.id}`"
        />
        <div
          :id="`image-reply-help-${inbox.id}`"
          class="flex flex-wrap items-start justify-between gap-x-3 gap-y-1 text-xs"
        >
          <span :class="replyInvalid ? 'text-n-ruby-9' : 'text-n-slate-11'">
            {{
              replyInvalid
                ? t('INBOX_MGMT.WHATSAPP_IMAGES.REPLY_ERROR')
                : t('INBOX_MGMT.WHATSAPP_IMAGES.REPLY_HELP')
            }}
          </span>
          <span class="shrink-0 tabular-nums text-n-slate-11">
            {{
              t('INBOX_MGMT.WHATSAPP_IMAGES.REPLY_COUNT', {
                count: replyLength,
              })
            }}
          </span>
        </div>
      </div>
      <div>
        <Button
          type="submit"
          :is-loading="saving"
          :disabled="saving || !changed || replyInvalid"
        >
          {{ t('INBOX_MGMT.WHATSAPP_IMAGES.SAVE') }}
        </Button>
      </div>
    </form>
  </SettingsSection>
</template>
