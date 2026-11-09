require 'rails_helper'

RSpec.describe SiteConfig, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:organization_name) }

    it 'validates email format' do
      config = build(:site_config, contact_email: 'invalid-email')
      expect(config).not_to be_valid
      expect(config.errors[:contact_email]).to include('must be a valid email')
    end

    it 'allows blank email' do
      config = build(:site_config, contact_email: '')
      expect(config).to be_valid
    end

    it 'accepts valid email' do
      config = build(:site_config, contact_email: 'contact@example.com')
      expect(config).to be_valid
    end
  end

  describe 'attachments' do
    it { is_expected.to have_one_attached(:favicon) }
    it { is_expected.to have_one_attached(:banner_image) }
  end

  describe '.instance' do
    it 'creates a site config if none exists' do
      expect(described_class.count).to eq(0)
      config = described_class.instance
      expect(config).to be_persisted
      expect(described_class.count).to eq(1)
    end

    it 'returns existing site config' do
      existing = create(:site_config)
      config = described_class.instance
      expect(config.id).to eq(existing.id)
    end

    it 'creates with default organization name' do
      config = described_class.instance
      expect(config.organization_name).to eq('EventManager')
    end

    it 'always uses id = 1' do
      config = described_class.instance
      expect(config.id).to eq(1)
    end
  end

  describe '.current' do
    it 'is an alias for .instance' do
      config = described_class.current
      expect(config).to eq(described_class.instance)
    end
  end

  describe '#host_contact_response_text' do
    it 'uses a patient default when nothing is saved' do
      config = described_class.new(organization_name: 'EventManager')

      expect(config.host_contact_response_text).to eq(described_class::DEFAULT_HOST_CONTACT_RESPONSE)
      expect(config.host_contact_response_text).to include('forwarded to the hosts')
      expect(config.host_contact_response_text).to include('patient about a reply')
    end

    it 'uses the saved message' do
      config = described_class.new(host_contact_response: 'The hosts have your note.')

      expect(config.host_contact_response_text).to eq('The hosts have your note.')
    end
  end

  describe 'singleton pattern' do
    it 'maintains only one record with id = 1' do
      # Create via factory (uses id: 1)
      create(:site_config)

      # Instance should return the same record
      instance = described_class.instance

      expect(described_class.count).to eq(1)
      expect(instance.id).to eq(1)
    end

    it 'enforces singleton via database constraint' do
      create(:site_config)

      # Attempting to create another record with different id should fail
      expect {
        described_class.create!(id: 2, organization_name: 'Another Org')
      }.to raise_error(ActiveRecord::StatementInvalid, /site_configs_singleton/)
    end
  end

  describe 'factory' do
    it 'creates a valid site config' do
      config = build(:site_config)
      expect(config).to be_valid
    end

    it 'creates config with favicon' do
      config = build(:site_config, :with_favicon)
      expect(config.favicon).to be_attached
    end

    it 'creates config with banner' do
      config = build(:site_config, :with_banner)
      expect(config.banner_image).to be_attached
    end

    it 'creates minimal config' do
      config = build(:site_config, :minimal)
      expect(config).to be_valid
      expect(config.contact_email).to be_nil
      expect(config.footer_text).to be_nil
    end

    it 'returns existing record if one exists' do
      first = create(:site_config)
      second = create(:site_config)
      expect(first.id).to eq(second.id)
    end
  end
end
