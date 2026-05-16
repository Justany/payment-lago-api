# frozen_string_literal: true

module PaymentProviders
  class PawapayService < BaseService
    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "pawapay"
      )

      @pawapay_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::PawapayProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = pawapay_provider.code

      pawapay_provider.api_key = args[:api_key] if args.key?(:api_key)
      pawapay_provider.code = args[:code] if args.key?(:code)
      pawapay_provider.name = args[:name] if args.key?(:name)
      pawapay_provider.sandbox = args[:sandbox] if args.key?(:sandbox)
      pawapay_provider.default_country = args[:default_country] if args.key?(:default_country)
      pawapay_provider.default_correspondent = args[:default_correspondent] if args.key?(:default_correspondent)
      pawapay_provider.webhook_secret = args[:webhook_secret] if args.key?(:webhook_secret)
      pawapay_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)

      pawapay_provider.save!

      if payment_provider_code_changed?(pawapay_provider, old_code, args)
        pawapay_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.pawapay_provider = pawapay_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    attr_reader :pawapay_provider
  end
end
