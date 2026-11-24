require 'rails_helper'

RSpec.describe BotSafetyReviewRun do
  it 'preserves audit notes when the author is deleted and cleans runs when the account is deleted' do
    account = create(:account)
    user = create(:user)
    run = described_class.create!(account: account, user: user, idempotency_key: 'lifecycle-test', cutoff_at: Time.current, high_water_id: 0)
    item = run.items.create!(message_id: 1, conversation_id: 1)
    note = item.notes.create!(user: user, verdict: 'observing', note: 'Keep observing')
    user.destroy!
    expect(run.reload.user_id).to be_nil
    expect(note.reload.user_id).to be_nil
    expect(note.note).to eq('Keep observing')
    account.destroy!
    expect(described_class.exists?(run.id)).to be(false)
    expect(BotSafetyReviewNote.exists?(note.id)).to be(false)
  end
end
