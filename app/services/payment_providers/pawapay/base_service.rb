# frozen_string_literal: true

module PaymentProviders
  module Pawapay
    class BaseService < ::BaseService
      def initialize(payment_provider)
        @payment_provider = payment_provider

        super
      end

      protected

      attr_reader :payment_provider

      delegate :organization, :organization_id, to: :payment_provider

      def headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{payment_provider.api_key}"
        }
      end

      def http_client(endpoint)
        LagoHttpClient::Client.new("#{payment_provider.api_base_url}#{endpoint}")
      end

      def deliver_error_webhook(action:, error:)
        SendWebhookJob.perform_later(
          "payment_provider.error",
          payment_provider,
          provider_error: {
            source: "pawapay",
            action: action,
            message: error.message,
            code: error.error_code
          }
        )
      end
    end
  end
end
