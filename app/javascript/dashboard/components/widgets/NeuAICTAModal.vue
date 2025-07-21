<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useNeuAI } from 'dashboard/composables/useNeuAI';
import { NEUAI_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  emits: ['close'],

  setup() {
    const { updateUISettings } = useUISettings();
    const { recordAnalytics } = useNeuAI();
    const v$ = useVuelidate();

    return { updateUISettings, v$, recordAnalytics };
  },
  data() {
    return {
      value: '',
    };
  },
  validations: {
    value: {
      required,
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },

    onDismiss() {
      useAlert(this.$t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.DISMISS_MESSAGE'));
      this.updateUISettings({
        is_neuai_cta_modal_dismissed: true,
      });
      this.onClose();
    },

    async finishNeuAI() {
      const payload = {
        app_id: 'neuai',
        settings: {
          api_key: this.value,
        },
      };
      try {
        await this.$store.dispatch('integrations/createHook', payload);
        this.alertMessage = this.$t(
          'INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.SUCCESS_MESSAGE'
        );
        this.recordAnalytics(NEUAI_EVENTS.ADDED_AI_INTEGRATION_VIA_CTA_BUTTON);
        this.onClose();
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.ADD.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
    // openNeuAIDoc() {
    //   window.open('https://neuai.neutron.sg', '_blank');
    // },
  },
};
</script>

<template>
  <div class="flex-1 px-0 min-w-0">
    <woot-modal-header
      :header-title="$t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.TITLE')"
      :header-content="$t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.DESC')"
    />
    <form
      class="flex flex-col flex-wrap modal-content"
      @submit.prevent="finishNeuAI"
    >
      <div class="mt-2 w-full">
        <woot-input
          v-model="value"
          type="text"
          :class="{ error: v$.value.$error }"
          :placeholder="
            $t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.KEY_PLACEHOLDER')
          "
          @blur="v$.value.$touch"
        />
      </div>
      <div class="flex flex-row gap-2 justify-between px-0 py-2 w-full">
        <!-- <NextButton
          ghost
          type="button"
          class="!px-3"
          :label="
            $t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.BUTTONS.NEED_HELP')
          "
          @click.prevent="oNeupenAIDoc"
        /> -->
        <div class="flex gap-1 items-center">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.BUTTONS.DISMISS')"
            @click.prevent="onDismiss"
          />
          <NextButton
            type="submit"
            :disabled="v$.value.$invalid"
            :label="$t('INTEGRATION_SETTINGS.NEUAI.CTA_MODAL.BUTTONS.FINISH')"
          />
        </div>
      </div>
    </form>
  </div>
</template>
