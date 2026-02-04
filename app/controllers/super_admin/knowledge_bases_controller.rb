class SuperAdmin::KnowledgeBasesController < SuperAdmin::ApplicationController
  before_action :set_knowledge_base, only: [:show, :edit, :update, :destroy]

  def index
    @knowledge_bases = Kbase::KnowledgeBase.includes(:account).ordered
  end

  def show; end

  def new
    @knowledge_base = Kbase::KnowledgeBase.new
    @accounts = Account.order(:name)
  end

  def edit
    @accounts = Account.order(:name)
  end

  def create
    @knowledge_base = Kbase::KnowledgeBase.new(knowledge_base_params)

    create_neuai_dataset if params[:create_in_neuai] == '1' && @knowledge_base.neuai_dataset_id.blank?

    if @knowledge_base.save
      redirect_to super_admin_knowledge_bases_path,
                  notice: 'Knowledge base was successfully created.'
    else
      @accounts = Account.order(:name)
      render :new, status: :unprocessable_entity
    end
  rescue Kbase::NeuaiClient::Error => e
    @accounts = Account.order(:name)
    flash.now[:error] = "NeuAI Error: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def update
    if @knowledge_base.update(knowledge_base_params)
      redirect_to super_admin_knowledge_bases_path,
                  notice: 'Knowledge base was successfully updated.'
    else
      @accounts = Account.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    delete_neuai_dataset if params[:delete_from_neuai] == '1' && @knowledge_base.neuai_dataset_id.present?

    @knowledge_base.destroy
    redirect_to super_admin_knowledge_bases_path,
                notice: 'Knowledge base was successfully deleted.'
  rescue Kbase::NeuaiClient::Error => e
    redirect_to super_admin_knowledge_bases_path,
                alert: "Deleted locally but NeuAI error: #{e.message}"
  end

  def check_status
    ids = params[:ids].to_s.split(',').map(&:to_i)
    knowledge_bases = Kbase::KnowledgeBase.where(id: ids)

    statuses = {}
    client = Kbase::NeuaiClient.new

    knowledge_bases.each do |kb|
      statuses[kb.id] = if kb.neuai_dataset_id.blank?
                          'not_linked'
                        elsif client.dataset_exists?(kb.neuai_dataset_id)
                          'connected'
                        else
                          'missing'
                        end
    end

    render json: { statuses: statuses }
  rescue Kbase::NeuaiClient::ConfigurationError
    render json: { statuses: {}, error: 'NeuAI not configured' }
  rescue Kbase::NeuaiClient::Error => e
    render json: { statuses: {}, error: e.message }, status: :service_unavailable
  end

  private

  def set_knowledge_base
    @knowledge_base = Kbase::KnowledgeBase.find(params[:id])
  end

  def knowledge_base_params
    params.require(:kbase_knowledge_base).permit(:account_id, :name, :description, :neuai_dataset_id)
  end

  def create_neuai_dataset
    client = Kbase::NeuaiClient.new
    account = Account.find(@knowledge_base.account_id)
    dataset_name = "account_#{account.id}_#{@knowledge_base.name}"
    response = client.create_dataset(name: dataset_name, description: @knowledge_base.description)
    @knowledge_base.neuai_dataset_id = response['id']
  end

  def delete_neuai_dataset
    client = Kbase::NeuaiClient.new
    client.delete_dataset(@knowledge_base.neuai_dataset_id)
  end
end
