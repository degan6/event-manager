require 'rails_helper'

RSpec.describe HostContact, type: :model do
  describe 'validations' do
    it 'requires a real email and a message' do
      contact = described_class.new(email: 'not-an-email', message: '   ')

      expect(contact).not_to be_valid
      expect(contact.errors[:email]).to include('must be a valid email')
      expect(contact.errors[:message]).to include("can't be blank")
    end

    it 'accepts a message with a normal email address' do
      contact = described_class.new(email: ' guest@example.com ', name: 'Pat', message: ' Hello ')

      expect(contact).to be_valid
      expect(contact.email).to eq('guest@example.com')
      expect(contact.message).to eq('Hello')
    end

    it 'strips line breaks out of the name' do
      contact = described_class.new(name: "Pat\nBcc: evil@example.com")

      expect(contact.name).to eq('Pat Bcc: evil@example.com')
    end
  end
end
