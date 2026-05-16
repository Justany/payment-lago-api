# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::PawapayProvider do
  subject(:pawapay_provider) { build(:pawapay_provider, attributes) }

  let(:attributes) { {} }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:api_key) }

  describe "validations" do
    it "validates uniqueness of the code" do
      expect(pawapay_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "#api_key" do
    let(:api_key) { SecureRandom.uuid }

    before { pawapay_provider.api_key = api_key }

    it "returns the api key" do
      expect(pawapay_provider.api_key).to eq api_key
    end
  end

  describe "#api_base_url" do
    context "when sandbox flag is true" do
      let(:attributes) { {sandbox: true} }

      it "returns sandbox base url" do
        expect(pawapay_provider.api_base_url).to eq("https://api.sandbox.pawapay.io")
      end
    end

    context "when sandbox flag is false" do
      let(:attributes) { {sandbox: false} }

      it "returns production base url" do
        expect(pawapay_provider.api_base_url).to eq("https://api.pawapay.io")
      end
    end
  end

  describe "#environment" do
    it "returns :test when sandbox" do
      pawapay_provider.sandbox = true
      expect(pawapay_provider.environment).to eq(:test)
    end

    it "returns :live when not sandbox" do
      pawapay_provider.sandbox = false
      expect(pawapay_provider.environment).to eq(:live)
    end
  end

  describe "#payment_type" do
    it "returns 'pawapay'" do
      expect(pawapay_provider.payment_type).to eq("pawapay")
    end
  end

  describe "#webhook_end_point" do
    let(:organization_id) { SecureRandom.uuid }
    let(:code) { "test_code" }
    let(:lago_api_url) { "https://api.getlago.com" }

    before do
      pawapay_provider.organization_id = organization_id
      pawapay_provider.code = code
      allow(ENV).to receive(:[]).with("LAGO_API_URL").and_return(lago_api_url)
    end

    it "returns the correct webhook endpoint URL" do
      expected_url = "#{lago_api_url}/webhooks/pawapay/#{organization_id}?code=#{code}"
      expect(pawapay_provider.webhook_end_point.to_s).to eq(expected_url)
    end
  end

  describe "#determine_payment_status" do
    it "maps processing statuses" do
      %w[ACCEPTED ENQUEUED PROCESSING IN_RECONCILIATION].each do |s|
        expect(pawapay_provider.determine_payment_status(s)).to eq(:processing)
      end
    end

    it "maps COMPLETED to :succeeded" do
      expect(pawapay_provider.determine_payment_status("COMPLETED")).to eq(:succeeded)
    end

    it "maps failed statuses" do
      %w[FAILED REJECTED DUPLICATE_IGNORED].each do |s|
        expect(pawapay_provider.determine_payment_status(s)).to eq(:failed)
      end
    end
  end

  describe "#payable_payment_status" do
    it "returns 'pending' for processing statuses" do
      expect(pawapay_provider.payable_payment_status("PROCESSING")).to eq("pending")
    end

    it "returns 'succeeded' for COMPLETED" do
      expect(pawapay_provider.payable_payment_status("COMPLETED")).to eq("succeeded")
    end

    it "returns 'failed' for FAILED" do
      expect(pawapay_provider.payable_payment_status("FAILED")).to eq("failed")
    end
  end
end
