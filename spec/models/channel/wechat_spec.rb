require 'rails_helper'

RSpec.describe Channel::Wechat do
  let(:wechat_channel) { create(:channel_wechat) }

  describe '#send_message_on_wechat' do
    it 'sends a miniprogram page payload from message content attributes' do
      message = create(
        :message,
        message_type: :outgoing,
        content: '您的订单已准备好',
        content_attributes: {
          wechat_payload: {
            msgtype: 'miniprogrampage',
            miniprogrampage: {
              title: '您的订单已准备好',
              appid: 'wx123',
              pagepath: '/pages/order',
              thumb_media_id: 'media123'
            }
          }
        },
        conversation: create(:conversation, inbox: wechat_channel.inbox)
      )

      allow(wechat_channel).to receive(:get_access_token).and_return('ACCESS_TOKEN')
      stub_request(:post, "#{wechat_channel.wechat_api_url}/message/custom/send?access_token=ACCESS_TOKEN")
        .with do |request|
          body = JSON.parse(request.body)
          body == {
            'touser' => message.conversation.contact_inbox.source_id,
            'msgtype' => 'miniprogrampage',
            'miniprogrampage' => {
              'title' => '您的订单已准备好',
              'appid' => 'wx123',
              'pagepath' => '/pages/order',
              'thumb_media_id' => 'media123'
            }
          }
        end
        .to_return(
          status: 200,
          body: { errcode: 0, errmsg: 'ok' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(wechat_channel.send_message_on_wechat(message)).to eq('ok')
    end
  end
end
