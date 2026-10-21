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
