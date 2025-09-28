# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_dhcp_v4_scope) do
  let(:scope_resource) do
    described_class.new(name: 'wired_network', subnet: '172.24.132.0/24')
  end

  it 'defaults the config path to /etc/kea/kea-dhcp4.conf' do
    expect(scope_resource[:config_path]).to eq('/etc/kea/kea-dhcp4.conf')
  end

  it 'defaults id to :auto' do
    expect(scope_resource[:id]).to eq(:auto)
  end

  it 'rejects non-integer ids' do
    expect {
      described_class.new(name: 'bad', subnet: '192.0.2.0/24', id: 'not-a-number')
    }.to raise_error(Puppet::ResourceError, %r{must be an integer})
  end

  it 'requires a subnet when ensure is present' do
    expect {
      described_class.new(name: 'missing_subnet')
    }.to raise_error(Puppet::ResourceError, %r{Subnet is a required property})
  end

  context 'when validating subnets' do
    it 'rejects invalid subnet values' do
      expect {
        described_class.new(name: 'bad_subnet', subnet: 'not-a-subnet')
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv4 subnet})
    end

    it 'rejects subnets with invalid netmask' do
      expect {
        described_class.new(name: 'bad_subnet', subnet: '192.0.2.0\24')
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv4 subnet})
    end

    it 'rejects subnets missing their netmask suffix' do
      expect {
        described_class.new(name: 'bad_subnet', subnet: '192.0.2.0_24')
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv4 subnet})
    end

    it 'rejects subnets with an invalid lenght' do
      expect {
        described_class.new(name: 'bad_subnet', subnet: '192.0.0/24')
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv4 subnet})
    end
  end

  it 'validates option entries' do
    expect {
      described_class.new(name: 'bad_options', subnet: '10.0.0.0/24', options: ['invalid'])
    }.to raise_error(Puppet::ResourceError, %r{Each option must be a hash})
  end

  it 'accepts valid option hashes' do
    resource = described_class.new(
      name: 'valid_options',
      subnet: '10.0.0.0/24',
      options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
    )

    expect(resource[:options]).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
  end

  context 'when validating pools' do
    it 'accepts CIDR and range entries with spaces around the hyphen' do
      resource = described_class.new(
        name: 'valid_pools',
        subnet: '10.0.0.0/24',
        pools: ['10.0.0.0/28', '10.0.0.32 - 10.0.0.63'],
      )

      expect(resource[:pools]).to match_array(['10.0.0.0/28', '10.0.0.32 - 10.0.0.63'])
    end

    it 'rejects entries without spaces around the hyphen' do
      expect {
        described_class.new(name: 'bad_pools', subnet: '10.0.0.0/24', pools: ['10.0.0.1-10.0.0.10'])
      }.to raise_error(Puppet::ResourceError, %r{Pool entries must be a CIDR or IPv4 range})
    end

    it 'rejects entries that are not CIDR or IPv4 ranges' do
      expect {
        described_class.new(name: 'bad_pools', subnet: '10.0.0.0/24', pools: ['not-a-pool'])
      }.to raise_error(Puppet::ResourceError, %r{Pool entries must be a CIDR or IPv4 range})
    end
  end
end
