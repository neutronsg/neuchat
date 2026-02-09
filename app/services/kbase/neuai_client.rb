class Kbase::NeuaiClient
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class ApiError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  # Dataset API uses system-level ENV configuration, independent from Account-level NeuAI Hook
  # Dify has separate API keys for Dataset API vs Chat/Workflow API
  def initialize
    @base_url = ENV.fetch('NEUAI_DATASET_URL', nil)&.chomp('/')
    @api_key = ENV.fetch('NEUAI_DATASET_API_KEY', nil)

    raise ConfigurationError, 'NEUAI_DATASET_URL not configured' if @base_url.blank?
    raise ConfigurationError, 'NEUAI_DATASET_API_KEY not configured' if @api_key.blank?
  end

  # Dataset APIs
  def create_dataset(name:, description: nil)
    post('/v1/datasets', {
           name: name,
           description: description,
           indexing_technique: 'high_quality',
           permission: 'all_team_members'
         })
  end

  def delete_dataset(dataset_id)
    delete("/v1/datasets/#{dataset_id}")
  end

  def get_dataset(dataset_id)
    get("/v1/datasets/#{dataset_id}")
  end

  def dataset_exists?(dataset_id)
    get_dataset(dataset_id)
    true
  rescue ApiError => e
    return false if e.status == 404

    raise
  end

  def list_documents(dataset_id, page: 1, limit: 100)
    get("/v1/datasets/#{dataset_id}/documents", { page: page, limit: limit })
  end

  def get_document(dataset_id, document_id)
    get("/v1/datasets/#{dataset_id}/documents/#{document_id}")
  end

  def create_document_by_file(dataset_id, file, name:, separator: "\n\n")
    data = {
      name: name,
      indexing_technique: 'high_quality',
      process_rule: {
        mode: 'custom',
        rules: {
          pre_processing_rules: [],
          segmentation: {
            separator: separator,
            max_tokens: 1024,
            chunk_overlap: 50
          }
        }
      }
    }

    post_multipart("/v1/datasets/#{dataset_id}/document/create-by-file", file: file, data: data.to_json)
  end

  def update_document_by_file(dataset_id, document_id, file, name:, separator: "\n\n")
    data = {
      name: name,
      process_rule: {
        mode: 'custom',
        rules: {
          pre_processing_rules: [],
          segmentation: {
            separator: separator,
            max_tokens: 1024,
            chunk_overlap: 50
          }
        }
      }
    }

    post_multipart(
      "/v1/datasets/#{dataset_id}/documents/#{document_id}/update-by-file",
      file: file,
      data: data.to_json
    )
  end

  def create_document_by_text(dataset_id, name:, text:, separator: "\n\n")
    post("/v1/datasets/#{dataset_id}/document/create-by-text", {
           name: name,
           text: text,
           indexing_technique: 'high_quality',
           process_rule: {
             mode: 'custom',
             rules: {
               pre_processing_rules: [],
               segmentation: {
                 separator: separator,
                 max_tokens: 1024,
                 chunk_overlap: 50
               }
             }
           }
         })
  end

  def update_document_by_text(dataset_id, document_id, name:, text:, separator: "\n\n")
    # Dify API uses POST for document update, not PUT
    post("/v1/datasets/#{dataset_id}/documents/#{document_id}/update-by-text", {
           name: name,
           text: text,
           process_rule: {
             mode: 'custom',
             rules: {
               pre_processing_rules: [],
               segmentation: {
                 separator: separator,
                 max_tokens: 1024,
                 chunk_overlap: 50
               }
             }
           }
         })
  end

  def delete_document(dataset_id, document_id)
    delete("/v1/datasets/#{dataset_id}/documents/#{document_id}")
  end

  def update_document_status(dataset_id, document_ids, action:)
    patch("/v1/datasets/#{dataset_id}/documents/status/#{action}", {
            document_ids: Array(document_ids)
          })
  end

  private

  def headers
    {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def get(path, params = {})
    response = HTTParty.get("#{@base_url}#{path}", headers: headers, query: params)
    handle_response(response)
  end

  def post(path, body)
    response = HTTParty.post("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def put(path, body)
    response = HTTParty.put("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def patch(path, body)
    response = HTTParty.patch("#{@base_url}#{path}", headers: headers, body: body.to_json)
    handle_response(response)
  end

  def delete(path)
    response = HTTParty.delete("#{@base_url}#{path}", headers: headers)
    return nil if response.code == 204

    handle_response(response)
  end

  def post_multipart(path, file:, data:)
    response = HTTParty.post(
      "#{@base_url}#{path}",
      headers: { 'Authorization' => "Bearer #{@api_key}" },
      multipart: true,
      # HTTParty will use streaming multipart body by default for file uploads.
      # In practice, Dify/NeuAI may fail to parse streamed multipart requests and
      # respond with "Please upload your file.".
      # Disabling streaming makes HTTParty generate a standard multipart body.
      stream_body: false,
      body: {
        file: file,
        data: data
      }
    )
    handle_response(response)
  end

  def handle_response(response)
    return response.parsed_response if response.success?

    body = response.parsed_response
    message = body.is_a?(Hash) ? body['message'] : body.to_s
    raise ApiError.new(
      message.presence || 'API request failed',
      status: response.code,
      body: body
    )
  end
end
