# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Pawapay::ValidateIncomingWebhookService, type: :service do
  subject(:service) { described_class.new(payload:, signature:, payment_provider: provider) }

  let(:organization) { create(:organization) }
  let(:provider) { create(:pawapay_provider, organization:, webhook_secret:) }
  let(:body) { {"depositId" => "abc", "status" => "COMPLETED"}.to_json }
  let(:payload) { body }
  let(:signature) { nil }

  context "when no webhook_secret configured" do
    let(:webhook_secret) { nil }

    it "accepts any payload" do
      expect(service.call).to be_success
    end
  end

  context "when webhook_secret configured" do
    let(:webhook_secret) { "secret123" }

    context "without signature header" do
      let(:signature) { nil }

      it "fails" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
      end
    end

    context "with matching Content-Digest" do
      let(:signature) do
        digest = Base64.strict_encode64(OpenSSL::Digest.digest("SHA256", body))
        "sha-256=:#{digest}:"
      end

      it "succeeds" do
        expect(service.call).to be_success
      end
    end

    context "with mismatching Content-Digest" do
      let(:signature) { "sha-256=:wrong:" }

      it "fails" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
      end
    end
  end
end
