# AgentBot idle resolution (protocol v1)

This policy is separate from Account Auto Resolve and does not change `waiting_since` or human response metrics. Configure it on the AgentBot, not Account or Inbox. It applies across channels with an active AgentBot binding. It defaults off.

## Configuration

`bot_config.idle_auto_resolve_enabled` is a boolean. `idle_auto_resolve_after` is an integer in minutes (10–1439); the UI starts at 30 minutes. Account AgentBot create/update APIs also accept these two fields at the top level for multipart forms. Duration changes apply to the next eligible reply. Disabling the policy cancels existing deadlines. Re-enabling requires a new eligible reply.

`idle_protocol_seen_at` is read-only evidence of a compatible authenticated AgentBot reply, not a guarantee that every future reply supports the protocol. Each waiting period requires a fresh compatible reply. Existing bots remain compatible and never arm a deadline without the metadata below.

## Reply protocol

Use the existing public outgoing message API authenticated with the bound AgentBot token. Include these `content_attributes`:

```json
{
  "bot_idle_protocol": 1,
  "bot_awaiting_user": true,
  "bot_idle_notice": "We have not heard from you for a while, so this conversation will now end automatically.",
  "bot_trigger_message_id": 123,
  "bot_language": "en"
}
```

`bot_trigger_message_id` must identify the latest public incoming message. The notice must be a nonblank string of at most 12,000 characters, localized by the bot. A human or Contact sender cannot arm the deadline by copying metadata. Do not send `bot_awaiting_user=true` for error/fallback replies or explicit closure; `bot_close_reason` also prevents arming.

NeuChat calculates the deadline from reply creation time using its own configuration. It stores the deadline, reply ID and AgentBot ID on the conversation. The notice remains on the reply. API acceptance does not prove channel delivery or reading; known failed replies are not closed by this policy.

## Lifecycle

Public incoming or outgoing messages cancel the previous deadline; an eligible bot reply can then arm a new one. Private notes and activities do not reset the timer. Leaving pending, setting `ai_paused=true`, disabling the policy, or changing/removing the AgentBot binding cancels the deadline. Human public replies cancel it even if the status was not changed.

The existing five-minute scheduled job enqueues a separate idle-resolution job independent of Account Auto Resolve. Overdue records survive application restarts. Message insertion and idle closure lock the same conversation row. At execution, the job rechecks the active binding, configuration, state, pause flag, reply delivery failure and latest public interaction. It creates one notice and resolves in one transaction. Retrying after commit finds no deadline and does not duplicate the notice. Outgoing delivery remains the existing asynchronous pipeline.

Within the messaging window the job creates a public template message. Outside the window it records the existing internal notification-unavailable activity and still resolves. No new WhatsApp approved-template sending flow is introduced. The metadata `bot_close_reason=idle_timeout` and `bot_idle_source_reply_id` distinguishes notification records without storing a second conversation history.

Legacy Account Auto Resolve skips protocol-capable, enabled, pending bot conversations, including those waiting for a new bot reply. Once handed over to a human, the existing Account policy applies. Captain's separate enterprise workflow is not part of this protocol.

WhatsApp `lock_to_single_conversation` still controls whether new input reopens the old conversation or creates a new one. This feature does not change that setting or promise fresh context on reopening. A message arriving after the closure transaction uses the existing channel lifecycle.

## Rollout and validation

Apply the additive migration before the new NeuChat application code. Deploy the compatible bot contract separately; keep the setting off until validated. No old conversations are backfilled. Turning the setting off is the feature rollback; leave additive columns in place until all new code has been removed.

Validate first with a disposable local database, then representative channels (including Widget/API and WhatsApp): localization, new input at expiry, takeover, paused bot, failed replies, duplicate jobs, restart recovery, Account policy coexistence, and both single-conversation settings. Local database/message creation evidence is not channel delivery acceptance.
