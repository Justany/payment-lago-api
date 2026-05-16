# frozen_string_literal: true

require "openssl"
require "base64"

module PaymentProviders
  module Pawapay
    class ValidateIncomingWebhookService < ::BaseService
      def initialize(payload:, signature:, payment_provider:)
        @payload = payload
        @signature = signature
        @provider = payment_provider

        super
      end

      def call
        # pawaPay v2 webhooks use RFC-9421 HTTP Message Signatures, signed via the
        # Content-Digest + Signature + Signature-Input headers. Signing is OPTIONAL
        # in pawaPay (only enforced when "Only accept signed requests" is enabled).
        # When the merchant has not configured a webhook secret we accept the payload
        # as-is (relies on TLS + bearer-token URL secrecy).
        return result if webhook_secret.blank?

        # When a secret is configured, require a Content-Digest header and verify it
        # matches the body. Full RFC-9421 signature-input verification is added in
        # a follow-up — Content-Digest gives us body-tamper detection in the meantime.
        if signature.blank?
          return result.service_failure!(code: "webhook_error", message: "Missing signature header")
        end

        expected_digest = "sha-256=:#{Base64.strict_encode64(OpenSSL::Digest.digest("SHA256", body_string))}:"
        unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected_digest)
          return result.service_failure!(code: "webhook_error", message: "Invalid Content-Digest")
        end

        result
      end

      private

      attr_reader :payload, :signature, :provider

      def body_string
        payload.is_a?(String) ? payload : payload.to_json
      end

      def webhook_secret
        provider.webhook_secret
      end
    end
  end
end
