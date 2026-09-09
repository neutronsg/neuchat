require 'rails_helper'

describe AgentBotListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent_bot) { create(:agent_bot) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }

  describe '#message_created' do
    let(:event_name) { 'message.created' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message) }
    let!(:message) do
      create(:message, message_type: 'incoming',
                       account: account, inbox: inbox, conversation: conversation)
    end

    context 'when agent bot is not configured' do
      it 'does not send message to agent bot' do
        expect(AgentBots::WebhookDeliveryService).not_to receive(:enqueue)
        listener.message_created(event)
      end
    end

    context 'when agent bot is configured' do
      it 'sends message to agent bot' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookDeliveryService).to receive(:enqueue).with(
          url: agent_bot.outgoing_url,
          payload: message.webhook_data.merge(event: 'message_created'),
          webhook_type: :agent_bot_webhook
        ).once
        listener.message_created(event)
      end

      it 'does not send message to agent bot if url is empty' do
        agent_bot = create(:agent_bot, outgoing_url: '')
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookDeliveryService).not_to receive(:enqueue)
        listener.message_created(event)
      end
    end
  end

  describe '#webwidget_triggered' do
    context 'when agent bot is configured' do
      it 'does not send a widget lifecycle event to the agent bot' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)

        event = double
        allow(event).to receive(:data)
          .and_return(
            {
              contact_inbox: conversation.contact_inbox,
              event_info: { country: 'US' }
            }
          )
        expect(AgentBots::WebhookDeliveryService).not_to receive(:enqueue)

        listener.webwidget_triggered(event)
      end
    end
  end

  describe 'internal lifecycle events' do
    it 'does not forward conversation or message lifecycle events' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
      expect(AgentBots::WebhookDeliveryService).not_to receive(:enqueue)

      listener.conversation_opened(nil)
      listener.conversation_resolved(nil)
      listener.message_updated(nil)
    end
  end
end
