require 'rails_helper'

RSpec.describe Kbase::DocumentChunkSettings do
  describe '.default_process_rule' do
    it 'serializes pre processing rules as explicit booleans' do
      process_rule = described_class.default_process_rule

      expect(process_rule).to eq(
        {
          mode: 'custom',
          rules: {
            pre_processing_rules: [
              { id: 'remove_extra_spaces', enabled: false },
              { id: 'remove_urls_emails', enabled: false }
            ],
            segmentation: {
              separator: "\n\n",
              max_tokens: 1024,
              chunk_overlap: 50
            }
          }
        }
      )
    end
  end

  describe '.from_dify' do
    it 'normalizes null enabled values to false' do
      response = described_class.from_dify(
        document_process_rule: {
          mode: 'custom',
          rules: {
            pre_processing_rules: [
              { id: 'remove_extra_spaces', enabled: nil },
              { id: 'remove_urls_emails', enabled: nil }
            ],
            segmentation: {
              separator: "\n\n",
              max_tokens: 1024,
              chunk_overlap: 50
            }
          }
        },
        dataset_process_rule: nil
      )

      expect(response).to include(
        source: 'document',
        mode: 'custom',
        editable: true
      )
      expect(response[:pre_processing_rules]).to eq(
        {
          'remove_extra_spaces' => false,
          'remove_urls_emails' => false
        }
      )
    end
  end
end
