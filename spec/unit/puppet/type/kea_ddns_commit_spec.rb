# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_ddns_commit) do
  it 'uses name as the namevar (config path)' do
    r = described_class.new(name: '/etc/kea/kea-dhcp-ddns.conf')
    expect(r[:name]).to eq('/etc/kea/kea-dhcp-ddns.conf')
  end

  it 'defaults applied to committed' do
    r = described_class.new(name: '/etc/kea/kea-dhcp-ddns.conf')
    expect(r[:applied]).to eq('committed')
  end

  describe 'applied insync?' do
    let(:resource) { described_class.new(name: '/etc/kea/kea-dhcp-ddns.conf') }
    let(:prop) { resource.property(:applied) }

    it 'is in sync when value is committed' do
      expect(prop.insync?('committed')).to be true
    end

    it 'is out of sync when value is pending' do
      expect(prop.insync?('pending')).to be false
    end
  end
end
