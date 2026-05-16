# frozen_string_literal: true

module PaymentProviders
  module Pawapay
    class HandleEventService < ::BaseService
      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::PawapayService,
        "PaymentRequest" => PaymentRequests::Payments::PawapayService
      }.freeze

      def initialize(organization:, event_json:)
        @organization = organization
        @event_json = event_json.is_a?(String) ? JSON.parse(event_json) : event_json

        super
      end

      def call
        case event_kind
        when :deposit
          handle_deposit_event
        when :refund
          handle_refund_event
        when :payout
          # Payouts are outbound — Lago does not own a payout flow, ignore for now.
          result
        else
          result.service_failure!(code: "webhook_error", message: "Unknown pawaPay event payload")
        end
      end

      private

      attr_reader :organization, :event_json

      def event_kind
        return :deposit if event_json.key?("depositId") && !event_json.key?("refundId")
        return :refund if event_json.key?("refundId")
        return :payout if event_json.key?("payoutId")

        nil
      end

      def handle_deposit_event
        metadata = extract_metadata
        payable_type = metadata["lago_payable_type"].presence || "Invoice"
        klass = PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
          return result.service_failure!(code: "webhook_error", message: "Invalid lago_payable_type: #{payable_type}")
        end

        klass.new.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: event_json["depositId"],
          status: event_json["status"].to_s,
          metadata: metadata
        ).raise_if_error!

        result
      end

      def handle_refund_event
        metadata = extract_metadata

        CreditNotes::Refunds::PawapayService.new.update_status(
          provider_refund_id: event_json["refundId"],
          status: event_json["status"].to_s,
          metadata: metadata.symbolize_keys
        ).raise_if_error!

        result
      end

      def extract_metadata
        list = event_json["metadata"]
        return {} unless list.is_a?(Array)

        list.each_with_object({}) do |entry, acc|
          name = entry["fieldName"] || entry[:fieldName]
          value = entry["fieldValue"] || entry[:fieldValue]
          acc[name.to_s] = value if name
        end
      end
    end
  end
end
