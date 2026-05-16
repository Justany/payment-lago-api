# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::PawapayService, type: :service do
  subject(:pawapay_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe ".create_or_update" do
    it "creates a new pawapay provider" do
      result = pawapay_service.create_or_update(
        organization: organization,
        name: "pawaPay sandbox",
        code: "pawapay_sandbox",
        api_key: "test-key",
        sandbox: true,
        default_country: "ZMB",
        default_correspondent: "MTN_MOMO_ZMB"
      )

      expect(result).to be_success
      provider = result.pawapay_provider
      expect(provider).to be_persisted
      expect(provider.api_key).to eq("test-key")
      expect(provider.sandbox_mode?).to be(true)
      expect(provider.default_country).to eq("ZMB")
      expect(provider.default_correspondent).to eq("MTN_MOMO_ZMB")
    end

    it "updates an existing pawapay provider" do
      existing = create(:pawapay_provider, organization:, name: "old name")

      result = pawapay_service.create_or_update(
        organization: organization,
        id: existing.id,
        code: existing.code,
        name: "new name",
        api_key: "new-key"
      )

      expect(result).to be_success
      existing.reload
      expect(existing.name).to eq("new name")
      expect(existing.api_key).to eq("new-key")
    end

    it "fails when name missing" do
      result = pawapay_service.create_or_update(
        organization: organization,
        code: "no_name",
        api_key: "k"
      )

      expect(result).not_to be_success
    end
  end
end
