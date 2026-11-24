require 'rails_helper'
require 'digest'

RSpec.describe BotSafetyReviews::Evidence do
  let(:records) do
    [{ 'kind' => 'received', 'sequence' => 0, 'request_id' => 'r', 'payload' => {} },
     { 'kind' => 'plan', 'sequence' => 1, 'request_id' => 'r', 'attempt_id' => 'a',
       'payload' => { 'expectedChecks' => ['custom.input', 'custom.output'] } },
     { 'kind' => 'finished', 'sequence' => 2, 'request_id' => 'r', 'payload' => {} }]
  end
  let(:events) { [{ 'attempt_id' => 'a', 'provider' => 'custom', 'stage' => 'input', 'enforced' => true, 'status' => 'block' }] }
  let(:evidence) { { transcript: [], audit: { 'records' => records, 'events' => events, 'missingBlobs' => [] } } }

  it 'accepts an actual input block without requiring an impossible output check' do
    expect(described_class.complete?(evidence)).to be(true)
  end

  it 'does not let an older attempt or a shadow block hide missing checks' do
    events.first['attempt_id'] = 'old'
    expect(described_class.complete?(evidence)).to be(false)
    events.first['attempt_id'] = 'a'
    events.first['enforced'] = false
    expect(described_class.complete?(evidence)).to be(false)
  end

  it 'rejects a missing sequence, expired snapshot and changed canonical message' do
    records.last['sequence'] = 3
    expect(described_class.complete?(evidence)).to be(false)
    records.last['sequence'] = 2
    evidence[:audit]['missingBlobs'] = ['missing']
    expect(described_class.complete?(evidence)).to be(false)
    evidence[:audit]['missingBlobs'] = []
    records.first['payload'] = { 'references' => [{ 'id' => 3, 'hash' => Digest::SHA256.hexdigest('original') }] }
    evidence[:transcript] = [{ id: 3, content: 'changed' }]
    expect(described_class.complete?(evidence)).to be(false)
    evidence[:transcript][0][:content] = 'original'
    expect(described_class.complete?(evidence)).to be(true)
  end

  it 'does not treat AWS masked or blocked output as the unavailable original candidate' do
    %w[block masked].each do |status|
      events << { 'provider' => 'aws', 'stage' => 'output', 'status' => status }
      expect(described_class.complete?(evidence)).to be(false)
      events.pop
    end
  end

  it 'verifies reconstructed grouped text and rejects incorrect final hashes and recipes' do
    sources = { 1 => { content: '  hello  ' }, 2 => { content: 'world <disclosure>' } }
    turn = { 'recipe' => 'user_group', 'references' => [
      { 'id' => 1, 'hash' => Digest::SHA256.hexdigest(sources[1][:content]) },
      { 'id' => 2, 'hash' => Digest::SHA256.hexdigest(sources[2][:content]), 'stripSuffix' => '<disclosure>' }
    ], 'hash' => Digest::SHA256.hexdigest(JSON.generate({ userMessages: [{ messageId: 1, text: 'hello' }, { messageId: 2, text: 'world' }] })) }
    expect(described_class.turn_valid?(turn, sources)).to be(true)
    expect(described_class.turn_valid?(turn.merge('hash' => 'invalid'), sources)).to be(false)
    expect(described_class.turn_valid?(turn.merge('recipe' => 'unknown'), sources)).to be(false)
  end
end
