# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Pawapay::Payments::CreateService, type: :service do
  subject(:service) { described_class.new(payment:, reference:, metadata: {}) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "pawapay") }
  let(:provider) { create(:pawapay_provider, organization:, sandbox: true) }
  let!(:pawapay_customer) { create(:pawapay_customer, customer:, payment_provider: provider, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "ZMW", total_amount_cents: 10_000) }
  let(:payment) do
    create(:payment,
      organization:,
      customer:,
      payable: invoice,
      payment_provider: provider,
      payment_provider_customer: pawapay_customer,
      amount_cents: 10_000,
      amount_currency: "ZMW")
  end
  let(:reference) { "ref-1" }

  let(:deposit_url) { "https://api.sandbox.pawapay.io/v2/deposits" }

  before do
    customer.update!(payment_provider_code: provider.code)
  end

  context "when pawaPay accepts the deposit" do
    before do
      stub_request(:post, deposit_url).to_return(
        status: 200,
        body: {status: "ACCEPTED", depositId: "ignored-by-lago", created: Time.current.iso8601}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
    end

    it "marks the payment as processing with our generated depositId" do
      result = service.call

      expect(result).to be_success
      expect(payment.reload.provider_payment_id).to match(/\A[0-9a-f-]{36}\z/)
      expect(payment.status).to eq("ACCEPTED")
      expect(payment.payable_payment_status).to eq("pending")
    end

    it "POSTs the expected body" do
      service.call

      expect(WebMock).to have_requested(:post, deposit_url).with { |req|
        body = JSON.parse(req.body)
        body["currency"] == "ZMW" &&
          body["payer"]["type"] == "MMO" &&
          body["payer"]["accountDetails"]["phoneNumber"] == pawapay_customer.msisdn &&
          body["payer"]["accountDetails"]["provider"] == "MTN_MOMO_ZMB"
      }
    end
  end

  context "when pawaPay returns an error" do
    before do
      stub_request(:post, deposit_url).to_return(
        status: 400,
        body: {failureReason: {failureCode: "INVALID_PHONE_NUMBER"}}.to_json
      )
    end

    it "marks the payment as failed and returns a service failure" do
      result = service.call

      expect(result).not_to be_success
      expect(payment.reload.status).to eq("failed")
      expect(payment.payable_payment_status).to eq("failed")
    end
  end
end
