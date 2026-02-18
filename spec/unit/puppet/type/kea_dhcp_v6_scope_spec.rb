# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_dhcp_v6_scope) do
  let(:scope_resource) do
    described_class.new(name: 'wired_network', subnet: '2001:db8:1::/64')
  end

  it 'defaults the config path to /etc/kea/kea-dhcp6.conf' do
    expect(scope_resource[:config_path]).to eq('/etc/kea/kea-dhcp6.conf')
  end

  it 'defaults id to :auto' do
    expect(scope_resource[:id]).to eq(:auto)
  end

  it 'rejects non-integer ids' do
    expect {
      described_class.new(name: 'bad', subnet: '2001:db8::/32', id: 'not-a-number')
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
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv6 subnet})
    end

    it 'rejects subnets missing their prefix length' do
      expect {
        described_class.new(name: 'bad_subnet', subnet: '2001:db8::')
      }.to raise_error(Puppet::ResourceError, %r{Invalid ipv6 subnet})
    end

    it 'accepts valid IPv6 subnets' do
      resource = described_class.new(name: 'valid', subnet: '2001:db8:1::/64')
      expect(resource[:subnet]).to eq('2001:db8:1::/64')
    end

    it 'accepts shortened IPv6 subnets' do
      resource = described_class.new(name: 'valid', subnet: 'fd00::/8')
      expect(resource[:subnet]).to eq('fd00::/8')
    end
  end

  it 'validates option entries' do
    expect {
      described_class.new(name: 'bad_options', subnet: '2001:db8::/32', options: ['invalid'])
    }.to raise_error(Puppet::ResourceError, %r{Each option must be a hash})
  end

  it 'accepts valid option hashes' do
    resource = described_class.new(
      name: 'valid_options',
      subnet: '2001:db8::/32',
      options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
    )

    expect(resource[:options]).to eq([{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }])
  end

  context 'when validating pools' do
    it 'accepts IPv6 CIDR pool entries' do
      resource = described_class.new(
        name: 'valid_pools',
        subnet: '2001:db8:1::/64',
        pools: ['2001:db8:1:05::/80'],
      )

      expect(resource[:pools]).to match_array(['2001:db8:1:05::/80'])
    end

    it 'accepts IPv6 range entries with spaces around the hyphen' do
      resource = described_class.new(
        name: 'valid_pools',
        subnet: '2001:db8:1::/64',
        pools: ['2001:db8:1::1 - 2001:db8:1::ffff'],
      )

      expect(resource[:pools]).to match_array(['2001:db8:1::1 - 2001:db8:1::ffff'])
    end

    it 'rejects entries without spaces around the hyphen' do
      expect {
        described_class.new(name: 'bad_pools', subnet: '2001:db8::/32', pools: ['2001:db8::1-2001:db8::ff'])
      }.to raise_error(Puppet::ResourceError, %r{Pool entries must be an IPv6 CIDR or range})
    end

    it 'rejects entries that are not valid IPv6 pools' do
      expect {
        described_class.new(name: 'bad_pools', subnet: '2001:db8::/32', pools: ['not-a-pool'])
      }.to raise_error(Puppet::ResourceError, %r{Pool entries must be an IPv6 CIDR or range})
    end
  end

  context 'when validating pd_pools' do
    it 'accepts valid prefix delegation pools' do
      resource = described_class.new(
        name: 'pd_scope',
        subnet: '2001:db8:1::/64',
        pd_pools: [{ 'prefix' => '3000:1::', 'prefix-len' => 64, 'delegated-len' => 96 }],
      )

      expect(resource[:pd_pools]).to eq([{ 'prefix' => '3000:1::', 'prefix-len' => 64, 'delegated-len' => 96 }])
    end

    it 'rejects pd_pools that are not hashes' do
      expect {
        described_class.new(name: 'bad_pd', subnet: '2001:db8::/32', pd_pools: ['invalid'])
      }.to raise_error(Puppet::ResourceError, %r{Each pd-pool entry must be a hash})
    end

    it 'rejects pd_pools missing the prefix key' do
      expect {
        described_class.new(name: 'bad_pd', subnet: '2001:db8::/32', pd_pools: [{ 'prefix-len' => 64, 'delegated-len' => 96 }])
      }.to raise_error(Puppet::ResourceError, %r{Each pd-pool must contain a prefix key})
    end

    it 'rejects pd_pools missing the prefix-len key' do
      expect {
        described_class.new(name: 'bad_pd', subnet: '2001:db8::/32', pd_pools: [{ 'prefix' => '3000::', 'delegated-len' => 96 }])
      }.to raise_error(Puppet::ResourceError, %r{Each pd-pool must contain a prefix-len key})
    end

    it 'rejects pd_pools missing the delegated-len key' do
      expect {
        described_class.new(name: 'bad_pd', subnet: '2001:db8::/32', pd_pools: [{ 'prefix' => '3000::', 'prefix-len' => 64 }])
      }.to raise_error(Puppet::ResourceError, %r{Each pd-pool must contain a delegated-len key})
    end

    it 'converts string numeric values to integers' do
      resource = described_class.new(
        name: 'pd_scope',
        subnet: '2001:db8:1::/64',
        pd_pools: [{ 'prefix' => '3000:1::', 'prefix-len' => '64', 'delegated-len' => '96' }],
      )

      expect(resource[:pd_pools].first['prefix-len']).to eq(64)
      expect(resource[:pd_pools].first['delegated-len']).to eq(96)
    end
  end
end
