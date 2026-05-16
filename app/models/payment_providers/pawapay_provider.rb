# frozen_string_literal: true

module PaymentProviders
  class PawapayProvider < BaseProvider
    # Lago payment_status -> pawaPay statuses mapping
    PROCESSING_STATUSES = %w[ACCEPTED ENQUEUED PROCESSING IN_RECONCILIATION].freeze
    SUCCESS_STATUSES = %w[COMPLETED].freeze
    FAILED_STATUSES = %w[FAILED REJECTED DUPLICATE_IGNORED].freeze

    # pawaPay payment status -> Lago payable_payment_status mapping
    PAYABLE_PAYMENT_STATUS_MAP = {
      "ACCEPTED" => "pending",
      "ENQUEUED" => "pending",
      "PROCESSING" => "pending",
      "IN_RECONCILIATION" => "pending",
      "COMPLETED" => "succeeded",
      "FAILED" => "failed",
      "REJECTED" => "failed",
      "DUPLICATE_IGNORED" => "failed"
    }.freeze

    SANDBOX_BASE_URL = "https://api.sandbox.pawapay.io"
    PRODUCTION_BASE_URL = "https://api.pawapay.io"

    secrets_accessors :api_key
    settings_accessors :sandbox, :default_country, :default_correspondent

    validates :api_key, presence: true

    def api_base_url
      sandbox_mode? ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
    end

    def sandbox_mode?
      ActiveModel::Type::Boolean.new.cast(sandbox)
    end

    def webhook_end_point
      URI.join(
        ENV["LAGO_API_URL"],
        "webhooks/pawapay/#{organization_id}?code=#{URI.encode_www_form_component(code)}"
      )
    end

    def environment
      sandbox_mode? ? :test : :live
    end

    def payment_type
      "pawapay"
    end

    def payable_payment_status(pawapay_status)
      PAYABLE_PAYMENT_STATUS_MAP[pawapay_status]
    end
  end
end
