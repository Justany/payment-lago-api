# frozen_string_literal: true

module CreditNotes
  module Refunds
    class PawapayService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Pawapay"

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        refund_id = SecureRandom.uuid
        pawapay_response = create_pawapay_refund(refund_id)
        return result unless pawapay_response

        pawapay_status = pawapay_response["status"] || "ACCEPTED"
        refund_status = pawapay_payment_provider.determine_payment_status(pawapay_status)

        refund = Refund.new(
          organization_id: credit_note.organization_id,
          credit_note:,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment_provider_customer(customer),
          amount_cents: credit_note.refund_amount_cents,
          amount_currency: credit_note.total_amount_currency&.upcase,
          status: refund_status,
          provider_refund_id: refund_id
        )
        refund.save!

        update_credit_note_status(refund.status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        result.refund = refund
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(message: e.error_body, code: e.error_code)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
        result.service_failure!(code: "pawapay_error", message: "#{e.error_code}: #{e.error_body}")
      end

      def update_status(provider_refund_id:, status:, metadata: {})
        refund = Refund.find_by(provider_refund_id:)
        return handle_missing_refund(metadata) unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        lago_status = pawapay_payment_provider.determine_payment_status(status)
        refund.update!(status: lago_status)
        update_credit_note_status(lago_status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        if lago_status.to_sym == :failed
          deliver_error_webhook(message: "Payment refund failed", code: nil)
          Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
          result.service_failure!(code: "refund_failed", message: "Refund failed to perform")
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_accessor :credit_note

      delegate :organization, :customer, :invoice, to: :credit_note

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present? && payment.provider_payment_id.present?
      end

      def payment
        return @payment if defined?(@payment)

        @payment = if credit_note.invoice.payments.succeeded.present?
          credit_note.invoice.payments.succeeded.order(created_at: :desc).first
        else
          Payment.where(payable_type: "PaymentRequest")
            .joins("INNER JOIN invoices_payment_requests ON invoices_payment_requests.payment_request_id = payments.payable_id")
            .joins("INNER JOIN payment_requests ON payment_requests.id = invoices_payment_requests.payment_request_id")
            .where("invoices_payment_requests.invoice_id = ?", credit_note.invoice_id)
            .where(payments: {payable_payment_status: "succeeded"})
            .where(payment_requests: {customer_id: credit_note.customer_id})
            .where(payment_requests: {payment_status: 1})
            .order("payments.created_at DESC")
            .first
        end
      end

      def pawapay_payment_provider
        @pawapay_payment_provider ||= payment_provider(customer)
      end

      def http_client
        @http_client ||= LagoHttpClient::Client.new("#{pawapay_payment_provider.api_base_url}/v2/refunds")
      end

      def headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{pawapay_payment_provider.api_key}"
        }
      end

      def create_pawapay_refund(refund_id)
        body = {
          refundId: refund_id,
          depositId: payment.provider_payment_id,
          amount: Money.from_cents(credit_note.refund_amount_cents, credit_note.total_amount_currency).to_f.to_s,
          currency: credit_note.total_amount_currency.to_s.upcase,
          clientReferenceId: credit_note.id.to_s,
          metadata: [
            {fieldName: "lago_customer_id", fieldValue: customer.id.to_s},
            {fieldName: "lago_credit_note_id", fieldValue: credit_note.id.to_s},
            {fieldName: "lago_invoice_id", fieldValue: invoice.id.to_s}
          ]
        }

        response = http_client.post_with_response(body, headers)
        JSON.parse(response.body)
      end

      def deliver_error_webhook(message:, code:)
        SendWebhookJob.perform_later(
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: payment_provider_customer(customer)&.provider_customer_id,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def handle_missing_refund(metadata)
        return result unless metadata&.key?(:lago_invoice_id)
        return result unless Invoice.find_by(id: metadata[:lago_invoice_id])

        result.not_found_failure!(resource: "pawapay_refund")
      end
    end
  end
end
