# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhooksController, type: :request do
  describe "POST /webhooks/pawapay/:organization_id" do
    let(:organization) { create(:organization) }
    let!(:provider) { create(:pawapay_provider, organization:) }
    let(:url) { "/webhooks/pawapay/#{organization.id}?code=#{provider.code}" }

    let(:deposit_payload) do
      {depositId: "d1", status: "COMPLETED", amount: "10.00", currency: "ZMW"}.to_json
    end

    it "returns 200 for a valid deposit callback" do
      post url, params: deposit_payload, headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 for a valid refund callback" do
      payload = {refundId: "r1", depositId: "d1", status: "COMPLETED"}.to_json
      post url, params: payload, headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 for a payout callback" do
      payload = {payoutId: "p1", status: "COMPLETED"}.to_json
      post url, params: payload, headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:ok)
    end

    context "when webhook_secret is configured" do
      let!(:provider) { create(:pawapay_provider, organization:, webhook_secret: "secret-key") }

      it "rejects request without Content-Digest" do
        post url, params: deposit_payload, headers: {"Content-Type" => "application/json"}
        expect(response).to have_http_status(:bad_request)
      end

      it "accepts request with valid Content-Digest" do
        digest = Base64.strict_encode64(OpenSSL::Digest.digest("SHA256", deposit_payload))
        post url,
          params: deposit_payload,
          headers: {
            "Content-Type" => "application/json",
            "Content-Digest" => "sha-256=:#{digest}:"
          }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
