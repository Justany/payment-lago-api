# frozen_string_literal: true

module PaymentProviders
  module Pawapay
    module Payments
      class CreateService < ::BaseService
        include Customers::PaymentProviderFinder

        PROVIDER_NAME = "Pawapay"

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          deposit_id = SecureRandom.uuid
          payment.provider_payment_id = deposit_id

          response = create_deposit(deposit_id)

          status = response&.dig("status") || "ACCEPTED"
          payment.status = status
          payment.payable_payment_status = pawapay_payment_provider.determine_payment_status(status)
          payment.save!

          result.payment = payment
          result
        rescue LagoHttpClient::HttpError => e
          prepare_failed_result(e)
        end

        private

        attr_reader :payment, :reference, :metadata, :invoice, :provider_customer

        delegate :customer, to: :invoice

        def create_deposit(deposit_id)
          body = {
            depositId: deposit_id,
            amount: format_amount(payment.amount_cents, payment.amount_currency),
            currency: payment.amount_currency.to_s.upcase,
            payer: {
              type: "MMO",
              accountDetails: {
                phoneNumber: provider_customer.msisdn,
                provider: provider_customer.correspondent.presence || pawapay_payment_provider.default_correspondent
              }
            },
            customerMessage: customer_message,
            clientReferenceId: reference.to_s.first(100),
            metadata: deposit_metadata
          }

          response = http_client.post_with_response(body, headers)
          JSON.parse(response.body)
        end

        def format_amount(amount_cents, currency)
          Money.from_cents(amount_cents, currency).to_f.to_s
        end

        def customer_message
          base = "Invoice #{invoice.number}"
          base.gsub(/[^A-Za-z0-9]/, "").first(22).presence || "InvoicePayment"
        end

        def deposit_metadata
          [
            {fieldName: "lago_invoice_id", fieldValue: invoice.id.to_s},
            {fieldName: "lago_invoice_number", fieldValue: invoice.number.to_s},
            {fieldName: "lago_customer_id", fieldValue: customer.id.to_s},
            {fieldName: "lago_organization_id", fieldValue: invoice.organization_id.to_s},
            {fieldName: "lago_payable_type", fieldValue: invoice.class.name.to_s, isPII: false}
          ]
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

        def pawapay_payment_provider
          @pawapay_payment_provider ||= payment_provider(customer)
        end

        def prepare_failed_result(error)
          result.error_message = error.error_body
          result.error_code = error.error_code

          payment.update!(status: :failed, payable_payment_status: :failed)

          result.service_failure!(code: "pawapay_error", message: "#{error.error_code}: #{error.error_body}")
        end
      end
    end
  end
end
