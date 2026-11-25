require 'rails_helper'

RSpec.describe 'AgentBot idle protocol integration', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:bot) { create(:agent_bot, account: account, bot_config: { idle_auto_resolve_enabled: true, idle_auto_resolve_after: 10 }) }
  let!(:binding) { create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }

  def input
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.contact, message_type: :incoming)
  end

  def reply(to: input, sender: bot, extra: {})
    attributes = { bot_idle_authorized: true, bot_idle_protocol: 1, bot_awaiting_user: true,
                   bot_idle_notice: '闲置自动结束', bot_trigger_message_id: to.id }.merge(extra)
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: sender,
                     message_type: :outgoing, private: false, content_attributes: attributes)
  end

  def expire
    travel 11.minutes
    Conversations::BotIdleResolutionJob.perform_now
    conversation.reload
  end

  def reject_image(id: 'image-rejection-id')
    conversation.contact_inbox.update!(source_id: '12025550109')
    params = { contacts: [{ wa_id: '12025550109', profile: { name: 'Local image test' } }],
               messages: [{ id: id, from: '12025550109', type: 'image', image: { id: 'not-downloaded', caption: 'ignored' } }] }
    Whatsapp::IncomingMessageService.new(inbox: inbox, params: params.with_indifferent_access).perform
    conversation.messages.outgoing.reorder(id: :desc).first
  end

  it 'delivers English for an OCA deadline armed with a legacy Chinese notice without rewriting history' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('OCA_BOT_ACCOUNT_ID', '').and_return(account.id.to_s)
    old_reply = reply
    expect(expire.status).to eq('resolved')
    notice = conversation.messages.reload.find { |message| message.content_attributes['bot_close_reason'] == 'idle_timeout' }
    expect(notice.content).to eq(I18n.t('conversations.oca_bot_idle_notice', locale: :en))
    expect(old_reply.reload.content_attributes['bot_idle_notice']).to eq('闲置自动结束')
  end

  it 'retains bot notices for tenants outside the configured OCA account' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('OCA_BOT_ACCOUNT_ID', '').and_return('other-account')
    old_reply = reply
    expect(Conversations::BotIdleState.delivery_notice(old_reply)).to eq('闲置自动结束')
  end

  it 'arms image-only conversations and closes once without a model reply' do
    rejected = reject_image
    expect(conversation.reload.bot_idle_reply_id).to eq(rejected.id)
    expect(rejected.content_attributes['bot_trigger_message_id']).to eq(conversation.messages.incoming.last.id)
    expect(conversation.messages.incoming.last.content).to be_nil
    expect(expire.status).to eq('resolved')
    expect { Conversations::BotIdleResolutionJob.perform_now }.not_to change(conversation.messages, :count)
  end

  it 'rearms after an image rejection, retains the prior notice and deduplicates the rejection' do
    reply
    travel 5.minutes
    rejected = reject_image
    expect(conversation.reload.bot_idle_deadline_at).to be_within(1.second).of(10.minutes.from_now)
    expect { reject_image }.not_to change(conversation.messages, :count)
    expect(rejected.content_attributes['bot_idle_notice']).to eq('闲置自动结束')
    expect(expire.status).to eq('resolved')
    expect(conversation.messages.last.content).to eq('闲置自动结束')
  end

  it 'does not close on a failed image rejection reply' do
    reject_image.update!(status: :failed)
    expect(expire.status).to eq('pending')
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
  end

  it 'cancels image rejection idle waits for new text and respects paused conversations' do
    reject_image
    input
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    conversation.update!(custom_attributes: { ai_paused: true })
    reject_image(id: 'paused-image')
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
  end

  it 'reopens a single conversation before arming the image rejection deadline' do
    inbox.update!(lock_to_single_conversation: true)
    conversation.update!(status: :resolved)
    rejected = reject_image
    expect(conversation.reload.status).to eq('pending')
    expect(conversation.bot_idle_reply_id).to eq(rejected.id)
    expect { reject_image }.not_to change(conversation.messages, :count)
    expect(expire.status).to eq('resolved')
  end

  it 'keeps local image waits isolated from other active conversations and legacy resolution' do
    account.update!(auto_resolve_after: 10, auto_resolve_ignore_waiting: true)
    bot.update!(bot_config: { idle_auto_resolve_enabled: true, idle_auto_resolve_after: 20 })
    other = create(:conversation, account: account, inbox: inbox, status: :pending, waiting_since: nil)
    other.update!(waiting_since: nil)
    reject_image
    expect(bot.reload.idle_protocol_seen_at).to be_nil
    expect(Conversations::BotIdleState.managed?(other.reload)).to be false
    travel 11.minutes
    Conversations::ResolutionJob.perform_now(account: account)
    expect(other.reload.status).to eq('resolved')
    expect(conversation.reload.status).to eq('pending')
    expect(expire.status).to eq('resolved')
  end

  it 'retains another protocol conversation deadline when rejecting an image' do
    other = create(:conversation, account: account, inbox: inbox, status: :pending)
    other_input = create(:message, conversation: other, message_type: :incoming)
    create(:message, conversation: other, sender: bot, message_type: :outgoing, content_attributes: {
             bot_idle_authorized: true, bot_idle_protocol: 1, bot_awaiting_user: true,
             bot_trigger_message_id: other_input.id, bot_idle_notice: 'Closing this chat.'
           })
    deadline = other.reload.bot_idle_deadline_at
    expect(deadline).to be_present
    reject_image
    expect(other.reload.bot_idle_deadline_at).to eq(deadline)
    expire
    expect(other.reload.status).to eq('resolved')
  end

  it 'arms persistently without clearing human waiting and resolves once with localized notice' do
    reply
    expect(bot.reload.idle_protocol_seen_at).to be_present
    expect(conversation.reload.bot_idle_deadline_at).to be_present
    expect(conversation.waiting_since).to be_present
    expect(expire.status).to eq('resolved')
    notices = -> { conversation.messages.reload.select { |m| m.content_attributes['bot_close_reason'] == 'idle_timeout' } }
    expect(notices.call.count).to eq(1)
    expect(notices.call.first.content).to eq('闲置自动结束')
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
  end

  it 'does not duplicate the notice on repeated jobs' do
    reply
    expire
    expect { Conversations::BotIdleResolutionJob.perform_now }.not_to change(conversation.messages, :count)
  end

  it 'closes after a delivered error notice without recording a successful answer or resolution' do
    notice = reply(extra: { bot_completed_turn: false })
    expect(conversation.reload.bot_idle_reply_id).to eq(notice.id)
    expect(notice.content_attributes['bot_outcome']).to be_nil
    expect(expire.status).to eq('resolved')
    closing = conversation.messages.reload.find { |message| message.content_attributes['bot_close_reason'] == 'idle_timeout' }
    expect(closing).to be_present
    expect(closing.content_attributes['bot_completed_turn']).not_to be true
    expect { Conversations::BotIdleResolutionJob.perform_now }.not_to change(conversation.messages, :count)
  end

  it 'cancels the error-notice wait if delivery fails or the user sends another message' do
    reply(extra: { bot_completed_turn: false }).update!(status: :failed)
    expect(expire.status).to eq('pending')
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    reply(extra: { bot_completed_turn: false })
    input
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
  end

  it 'cancels on new input and rearms only after its reply' do
    reply
    newer = input
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
    reply(to: newer)
    expect(conversation.reload.bot_idle_deadline_at).to be_present
  end

  it 'does not arm for a stale answer' do
    old = input
    input
    reply(to: old)
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
  end

  it 'cancels on takeover and does not revive when returned to pending' do
    reply
    conversation.update!(status: :open)
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    conversation.update!(status: :pending)
    expect(expire.status).to eq('pending')
  end

  it 'cancels on ai_paused' do
    reply
    conversation.update!(custom_attributes: { ai_paused: true })
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
  end

  it 'cancels on human reply without a status change' do
    reply
    reply(sender: create(:user, account: account))
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
  end

  it 'does not arm when disabled but records compatible capability' do
    bot.update!(idle_auto_resolve_enabled: false)
    reply
    expect(bot.reload.idle_protocol_seen_at).to be_present
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
  end

  it 'cancels existing waits when disabled and requires a new reply after re-enabling' do
    reply
    bot.update!(idle_auto_resolve_enabled: false)
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    bot.update!(idle_auto_resolve_enabled: true)
    expect(expire.status).to eq('pending')
  end

  it 'uses changed duration only on subsequent replies' do
    reply
    deadline = conversation.reload.bot_idle_deadline_at
    bot.update!(idle_auto_resolve_after: 20)
    expect(conversation.reload.bot_idle_deadline_at).to eq(deadline)
    reply
    expect(conversation.reload.bot_idle_deadline_at).to be > deadline
  end

  it 'rejects spoofed or closing/fallback protocol replies' do
    reply(extra: { bot_idle_protocol: 2 })
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    reply(extra: { bot_close_reason: 'turn_limit' })
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    reply(extra: { bot_awaiting_user: false })
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    reply(sender: create(:user, account: account))
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
  end

  it 'cancels on binding removal' do
    reply
    binding.destroy!
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(expire.status).to eq('pending')
  end

  it 'does not resolve a reply subsequently marked failed' do
    reply.update!(status: :failed)
    expect(expire.status).to eq('pending')
  end

  it 'preserves deadline on private notes' do
    reply
    deadline = conversation.reload.bot_idle_deadline_at
    create(:message, conversation: conversation, account: account, inbox: inbox, private: true)
    expect(conversation.reload.bot_idle_deadline_at).to eq(deadline)
  end

  it 'skips legacy resolution for managed bot conversations but preserves human behavior' do
    account.update!(auto_resolve_after: 10)
    reply
    conversation.update!(waiting_since: nil, last_activity_at: 1.hour.ago)
    Conversations::ResolutionJob.perform_now(account: account)
    expect(conversation.reload.status).to eq('pending')
    conversation.update!(status: :open)
    Conversations::ResolutionJob.perform_now(account: account)
    expect(conversation.reload.status).to eq('resolved')
  end

  it 'records activity instead of a public notice outside the messaging window' do
    reply
    travel 25.hours
    Conversations::BotIdleResolutionJob.perform_now
    expect(conversation.reload.status).to eq('resolved')
    notice = conversation.messages.reload.find { |m| m.content_attributes['bot_close_reason'] == 'idle_timeout' }
    expect(notice).to be_activity
  end

  it 'authenticates the reply protocol and rejects human sender impersonation' do
    incoming = input
    params = { content: 'A real API answer', message_type: 'outgoing', private: false,
               content_attributes: { bot_idle_protocol: 1, bot_awaiting_user: true, bot_idle_notice: '闲置结束', bot_trigger_message_id: incoming.id } }
    endpoint = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"
    post endpoint, params: params, headers: { api_access_token: bot.access_token.token }, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.reload.bot_idle_deadline_at).to be_present
    human = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: human)
    params[:sender_type] = 'AgentBot'
    params[:sender_id] = bot.id
    params[:content_attributes][:bot_idle_authorized] = true
    post endpoint, params: params, headers: human.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.reload.bot_idle_deadline_at).to be_nil
    expect(conversation.messages.reload.last.content_attributes['bot_idle_authorized']).to be_nil
  end

  it 'saves multipart configuration and prevents caller-written capability claims' do
    admin = create(:user, account: account, role: :administrator)
    patch "/api/v1/accounts/#{account.id}/agent_bots/#{bot.id}",
          params: { idle_auto_resolve_enabled: 'true', idle_auto_resolve_after: '25', idle_protocol_seen_at: Time.current },
          headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(bot.reload.idle_auto_resolve?).to be true
    expect(bot.idle_auto_resolve_after.to_i).to eq(25)
    expect(bot.idle_protocol_seen_at).to be_nil
  end

  %i[channel_api channel_widget].each do |factory|
    context "with #{factory}" do
      let(:channel) { create(factory, account: account) }

      it 'arms and resolves with one public localized notice' do
        reply
        expect(conversation.reload.bot_idle_deadline_at).to be_present
        expect(expire.status).to eq('resolved')
        notices = conversation.messages.select { |message| message.content_attributes['bot_close_reason'] == 'idle_timeout' }
        expect(notices.size).to eq(1)
        expect(notices.first).to be_template
        expect(notices.first.content).to eq('闲置自动结束')
      end

      it 'cancels on new input and rearms after the next reply' do
        reply
        incoming = input
        expect(conversation.reload.bot_idle_deadline_at).to be_nil
        reply(to: incoming)
        expect(conversation.reload.bot_idle_deadline_at).to be_present
      end

      it 'cancels on human takeover' do
        reply
        conversation.update!(status: :open)
        expect(conversation.reload.bot_idle_deadline_at).to be_nil
        expect(expire.status).to eq('open')
      end
    end
  end
end
