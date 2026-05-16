# frozen_string_literal: true

module PaymentRequests
  module Payments
    class PawapayService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Pawapay"

      def initialize(payable = nil)
        @payable = payable

        super(nil)
      end

      def create
        result.payable = payable
        return result.not_found_failure!(resource: "pawapay_customer") if customer&.pawapay_customer.blank?
        return result.not_found_failure!(resource: "pawapay_phone_number") if customer.pawapay_customer.msisdn.blank?
        return result unless should_process_payment?

        unless payable.total_amount_cents.positive?
          update_payable_payment_status(payment_status: :succeeded)
          return result
        end

        payable.increment_payment_attempts!

        deposit_id = SecureRandom.uuid
        pawapay_response = create_deposit(deposit_id)
        return result unless pawapay_response

        pawapay_status = pawapay_response["status"] || "ACCEPTED"

        payment = Payment.new(
          organization_id: payable.organization_id,
          payable: payable,
          customer:,
          payment_provider_id: pawapay_payment_provider.id,
          payment_provider_customer_id: customer.pawapay_customer.id,
          amount_cents: payable.amount_cents,
          amount_currency: payable.currency&.upcase,
          provider_payment_id: deposit_id,
          status: pawapay_payment_provider.determine_payment_status(pawapay_status)
        )
        payment.save!

        payable_payment_status = pawapay_payment_provider.payable_payment_status(pawapay_status)

        update_payable_payment_status(
          payment_status: payable_payment_status,
          processing: payment.status == "pending"
        )
        update_invoices_payment_status(
          payment_status: payable_payment_status,
          processing: payment.status == "pending"
        )

        result.payment = payment
        result.payable_payment_status = payable_payment_status
        result
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
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status: pawapay_payment_provider.determine_payment_status(status))

        processing = payment.status == "processing"
        payable_payment_status = pawapay_payment_provider.payable_payment_status(status)
        update_payable_payment_status(payment_status: payable_payment_status, processing:)
        update_invoices_payment_status(payment_status: payable_payment_status, processing:)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?
        result
      rescue BaseService::FailedResult => e
        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable&.payment_failed?
        result.fail_with_error!(e)
      end

      private

      attr_reader :payable

      delegate :organization, :customer, to: :payable

      def should_process_payment?
        return false if payable.payment_succeeded?
        return false if pawapay_payment_provider.blank?

        !!customer&.pawapay_customer
      end

      def pawapay_payment_provider
        @pawapay_payment_provider ||= payment_provider(customer)
      end

      def http_client
        @http_client ||= LagoHttpClient::Client.new("#{pawapay_payment_provider.api_base_url}/v2/deposits")
      end

      def headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{pawapay_payment_provider.api_key}"
        }
      end

      def create_deposit(deposit_id)
        body = {
          depositId: deposit_id,
          amount: Money.from_cents(payable.total_amount_cents, payable.currency).to_f.to_s,
          currency: payable.currency.to_s.upcase,
          payer: {
            type: "MMO",
            accountDetails: {
              phoneNumber: customer.pawapay_customer.msisdn,
              provider: customer.pawapay_customer.correspondent.presence || pawapay_payment_provider.default_correspondent
            }
          },
          customerMessage: "PR#{payable.id.to_s.first(20)}".gsub(/[^A-Za-z0-9]/, "").first(22),
          clientReferenceId: payable.id.to_s,
          metadata: [
            {fieldName: "lago_payable_id", fieldValue: payable.id.to_s},
            {fieldName: "lago_payable_type", fieldValue: payable.class.name},
            {fieldName: "lago_customer_id", fieldValue: customer.id.to_s},
            {fieldName: "lago_organization_id", fieldValue: payable.organization_id.to_s}
          ]
        }

        response = http_client.post_with_response(body, headers)
        JSON.parse(response.body)
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)
        nil
      end

      def create_payment(provider_payment_id:, metadata:)
        @payable = payable || PaymentRequest.find_by(id: metadata["lago_payable_id"])

        unless payable
          result.not_found_failure!(resource: "payment_request")
          return
        end

        payable.increment_payment_attempts!

        Payment.new(
          organization_id: payable.organization_id,
          payable:,
          customer:,
          payment_provider_id: pawapay_payment_provider.id,
          payment_provider_customer_id: customer.pawapay_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency&.upcase,
          provider_payment_id:
        )
      end

      def handle_missing_payment(organization_id, metadata)
        return result unless metadata&.key?("lago_payable_id")
        payment_request = PaymentRequest.find_by(id: metadata["lago_payable_id"], organization_id:)
        return result unless payment_request
        return result if payment_request.payment_failed?

        result.not_found_failure!(resource: "pawapay_payment")
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true, processing: false)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result.payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice: invoice,
            params: {
              payment_status:,
              ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def deliver_error_webhook(pawapay_error)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: customer.pawapay_customer&.provider_customer_id,
          provider_error: {
            message: pawapay_error.message,
            error_code: pawapay_error.error_code
          }
        })
      end
    end
  end
end
