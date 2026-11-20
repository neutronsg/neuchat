<script setup>
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { contentAttributes } = useMessageContext();
</script>

<template>
  <BaseBubble class="px-4 py-3 text-sm" data-bubble-name="unsupported">
    {{
      contentAttributes.whatsappImageRejected
        ? $t('CONVERSATION.WHATSAPP_IMAGE_REJECTED')
        : $t('CONVERSATION.UNSUPPORTED_MESSAGE')
    }}
  </BaseBubble>
</template>
