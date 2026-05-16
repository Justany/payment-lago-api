# frozen_string_literal: true

module PaymentProviderCustomers
  class PawapayCustomer < BaseCustomer
    settings_accessors :phone_number, :country, :correspondent

    def msisdn
      phone_number.to_s.gsub(/\D/, "")
    end
  end
end
