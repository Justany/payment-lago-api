# frozen_string_literal: true

module Invoices
  module Payments
    class PawapayService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Pawapay"

      def initialize(invoice = nil)
        @invoice = invoice

        super(nil)
      end

      def update_payment_status(organization_id:, provider_payment_id:, status:, metadata: {})
        payment_obj = Payment.find_or_initialize_by(provider_payment_id: provider_payment_id)
        payment = if payment_obj.persisted?
          payment_obj
        else
          create_payment(provider_payment_id:, metadata:)
        end

        return handle_missing_payment(organization_id, metadata) unless payment

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment_status = payment.payment_provider.determine_payment_status(status)
        payable_payment_status = payment.payment_provider.payable_payment_status(status)

        payment.update!(status: payment_status, payable_payment_status:)

        deliver_webhook if payable_payment_status.to_sym == :succeeded

        update_invoice_payment_status(payment_status: payable_payment_status, processing: payment_status == :processing)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url(_payment_intent)
        result.payment_url = nil
        result
      end

      private

      attr_reader :invoice

      delegate :organization, :customer, to: :invoice

      def pawapay_payment_provider
        @pawapay_payment_provider ||= payment_provider(customer)
      end

      def create_payment(provider_payment_id:, metadata:)
        @invoice ||= Invoice.find_by(id: metadata["lago_invoice_id"])
        unless @invoice
          result.not_found_failure!(resource: "invoice")
          return
        end

        increment_payment_attempts

        Payment.new(
          organization_id: @invoice.organization_id,
          payable: @invoice,
          customer:,
          payment_provider_id: pawapay_payment_provider.id,
          payment_provider_customer_id: customer.pawapay_customer.id,
          amount_cents: @invoice.total_due_amount_cents,
          amount_currency: @invoice.currency&.upcase,
          provider_payment_id:
        )
      end

      def handle_missing_payment(organization_id, metadata)
        return result unless metadata&.key?("lago_invoice_id")

        invoice = Invoice.find_by(id: metadata["lago_invoice_id"], organization_id:)
        return result if invoice.nil?
        return result if invoice.payment_failed?

        result.not_found_failure!(resource: "pawapay_payment")
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        Invoices::UpdateService.call(
          invoice: invoice.presence || result.invoice,
          params: {
            payment_status:,
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def deliver_webhook
        SendWebhookJob.perform_later("payment.succeeded", result.payment)
      end
    end
  end
end
