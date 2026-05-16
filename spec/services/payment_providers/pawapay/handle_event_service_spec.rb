# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Pawapay::HandleEventService, type: :service do
  subject(:service) { described_class.new(organization:, event_json:) }

  let(:organization) { create(:organization) }

  describe "deposit event" do
    let(:event_json) do
      {
        "depositId" => "deposit-123",
        "status" => "COMPLETED",
        "amount" => "100.00",
        "currency" => "ZMW",
        "metadata" => [
          {"fieldName" => "lago_payable_type", "fieldValue" => "Invoice"}
        ]
      }
    end

    it "dispatches to invoice payment service" do
      invoice_service = instance_double(Invoices::Payments::PawapayService)
      allow(Invoices::Payments::PawapayService).to receive(:new).and_return(invoice_service)
      allow(invoice_service).to receive(:update_payment_status)
        .and_return(BaseService::Result.new)

      service.call

      expect(invoice_service).to have_received(:update_payment_status).with(
        organization_id: organization.id,
        provider_payment_id: "deposit-123",
        status: "COMPLETED",
        metadata: hash_including("lago_payable_type" => "Invoice")
      )
    end

    context "when payable_type is PaymentRequest" do
      let(:event_json) do
        {
          "depositId" => "deposit-1",
          "status" => "COMPLETED",
          "metadata" => [{"fieldName" => "lago_payable_type", "fieldValue" => "PaymentRequest"}]
        }
      end

      it "dispatches to payment_request service" do
        pr_service = instance_double(PaymentRequests::Payments::PawapayService)
        allow(PaymentRequests::Payments::PawapayService).to receive(:new).and_return(pr_service)
        allow(pr_service).to receive(:update_payment_status)
          .and_return(BaseService::Result.new)

        service.call

        expect(pr_service).to have_received(:update_payment_status)
      end
    end
  end

  describe "refund event" do
    let(:event_json) do
      {
        "refundId" => "refund-1",
        "depositId" => "deposit-1",
        "status" => "COMPLETED"
      }
    end

    it "dispatches to refund service" do
      refund_service = instance_double(CreditNotes::Refunds::PawapayService)
      allow(CreditNotes::Refunds::PawapayService).to receive(:new).and_return(refund_service)
      allow(refund_service).to receive(:update_status).and_return(BaseService::Result.new)

      service.call

      expect(refund_service).to have_received(:update_status).with(
        provider_refund_id: "refund-1",
        status: "COMPLETED",
        metadata: {}
      )
    end
  end

  describe "payout event" do
    let(:event_json) { {"payoutId" => "p1", "status" => "COMPLETED"} }

    it "returns success without dispatch" do
      expect(service.call).to be_success
    end
  end

  describe "unknown event" do
    let(:event_json) { {"random" => "x"} }

    it "fails" do
      result = service.call
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
    end
  end
end
