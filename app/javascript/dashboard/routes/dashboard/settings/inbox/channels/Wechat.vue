<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      channelName: '',
      appName: '',
      appId: '',
      appSecret: '',
      encodingAesKey: '',
      token: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    channelName: { required },
    appName: { required },
    appId: { required },
    appSecret: { required },
    encodingAesKey: { required },
    token: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const wechatChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.channelName,
            channel: {
              type: 'wechat',
              app_name: this.appName,
              app_id: this.appId,
              app_secret: this.appSecret,
              encoding_aes_key: this.encodingAesKey,
              token: this.token,
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: wechatChannel.id,
          },
        });
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.ADD.WECHAT_CHANNEL.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <div
    class="border border-n-weak bg-n-solid-1 rounded-t-lg border-b-0 h-full w-full p-6 col-span-6 overflow-auto"
  >
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.WECHAT_CHANNEL.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.WECHAT_CHANNEL.DESC')"
    />
    <form
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createChannel()"
    >
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.channelName.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.CHANNEL_NAME.LABEL') }}
          <input
            v-model="channelName"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.CHANNEL_NAME.PLACEHOLDER')
            "
            @blur="v$.channelName.$touch"
          />
          <span v-if="v$.channelName.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.CHANNEL_NAME.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.appName.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_NAME.LABEL') }}
          <input
            v-model="appName"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_NAME.PLACEHOLDER')
            "
            @blur="v$.appName.$touch"
          />
          <span v-if="v$.appName.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_NAME.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.appId.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_ID.LABEL') }}
          <input
            v-model="appId"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_ID.PLACEHOLDER')
            "
            @blur="v$.appId.$touch"
          />
          <span v-if="v$.appId.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_ID.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.appSecret.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_SECRET.LABEL') }}
          <input
            v-model="appSecret"
            type="password"
            :placeholder="
              $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_SECRET.PLACEHOLDER')
            "
            @blur="v$.appSecret.$touch"
          />
          <span v-if="v$.appSecret.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.APP_SECRET.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.encodingAesKey.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.ENCODING_AES_KEY.LABEL') }}
          <input
            v-model="encodingAesKey"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.ENCODING_AES_KEY.PLACEHOLDER')
            "
            @blur="v$.encodingAesKey.$touch"
          />
          <span v-if="v$.encodingAesKey.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.ENCODING_AES_KEY.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.token.$error }">
          {{ $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.TOKEN.LABEL') }}
          <input
            v-model="token"
            type="text"
            :placeholder="$t('INBOX_MGMT.ADD.WECHAT_CHANNEL.TOKEN.PLACEHOLDER')"
            @blur="v$.token.$touch"
          />
          <span v-if="v$.token.$error" class="message">{{
            $t('INBOX_MGMT.ADD.WECHAT_CHANNEL.TOKEN.ERROR')
          }}</span>
        </label>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WECHAT_CHANNEL.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
