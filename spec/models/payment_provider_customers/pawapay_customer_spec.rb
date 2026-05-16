# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::PawapayCustomer do
  subject(:pawapay_customer) { build(:pawapay_customer) }

  describe "#msisdn" do
    it "strips non-digit characters" do
      pawapay_customer.phone_number = "+260 76 345 6789"
      expect(pawapay_customer.msisdn).to eq("260763456789")
    end

    it "returns empty string when phone is blank" do
      pawapay_customer.phone_number = nil
      expect(pawapay_customer.msisdn).to eq("")
    end
  end

  describe "settings_accessors" do
    it "exposes phone_number, country, correspondent" do
      pawapay_customer.phone_number = "260763456789"
      pawapay_customer.country = "ZMB"
      pawapay_customer.correspondent = "AIRTEL_OAPI_ZMB"

      expect(pawapay_customer.phone_number).to eq("260763456789")
      expect(pawapay_customer.country).to eq("ZMB")
      expect(pawapay_customer.correspondent).to eq("AIRTEL_OAPI_ZMB")
    end
  end
end
