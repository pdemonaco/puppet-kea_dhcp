# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_dhcp_v4_reservation) do
  let(:reservation_resource) do
    described_class.new(
      name: 'test-host',
      hostname: 'test-host.example.com',
      identifier_type: 'hw-address',
      identifier: '01:aa:bb:cc:dd:ee:ff',
      ip_address: '192.0.2.100',
    )
  end

  it 'defaults the config path to /etc/kea/kea-dhcp4.conf' do
    expect(reservation_resource[:config_path]).to eq('/etc/kea/kea-dhcp4.conf')
  end

  it 'defaults hostname to the resource name' do
    resource = described_class.new(
      name: 'default-name',
      identifier_type: 'hw-address',
      identifier: '01:aa:bb:cc:dd:ee:ff',
      ip_address: '192.0.2.100',
    )
    expect(resource[:hostname]).to eq('default-name')
  end

  it 'requires identifier_type when ensure is present' do
    expect {
      described_class.new(
        name: 'missing-type',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
      )
    }.to raise_error(Puppet::ResourceError, %r{identifier_type is required})
  end

  it 'requires identifier when ensure is present' do
    expect {
      described_class.new(
        name: 'missing-identifier',
        identifier_type: 'hw-address',
        ip_address: '192.0.2.100',
      )
    }.to raise_error(Puppet::ResourceError, %r{identifier is required})
  end

  it 'requires ip_address when ensure is present' do
    expect {
      described_class.new(
        name: 'missing-ip',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
      )
    }.to raise_error(Puppet::ResourceError, %r{ip_address is required})
  end

  context 'when validating identifier_type' do
    it 'accepts hw-address' do
      resource = described_class.new(
        name: 'hw-test',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier_type]).to eq(:'hw-address')
    end

    it 'accepts client-id' do
      resource = described_class.new(
        name: 'client-test',
        identifier_type: 'client-id',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier_type]).to eq(:'client-id')
    end

    it 'rejects invalid identifier types' do
      expect {
        described_class.new(
          name: 'bad-type',
          identifier_type: 'invalid-type',
          identifier: '01:aa:bb:cc:dd:ee:ff',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid value})
    end
  end

  context 'when validating MAC address identifiers' do
    it 'accepts MAC addresses with colon separators' do
      resource = described_class.new(
        name: 'colon-mac',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier]).to eq('01:aa:bb:cc:dd:ee:ff')
    end

    it 'accepts MAC addresses with hyphen separators' do
      resource = described_class.new(
        name: 'hyphen-mac',
        identifier_type: 'hw-address',
        identifier: '01-aa-bb-cc-dd-ee-ff',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier]).to eq('01-aa-bb-cc-dd-ee-ff')
    end

    it 'accepts lowercase hex digits' do
      resource = described_class.new(
        name: 'lower-mac',
        identifier_type: 'hw-address',
        identifier: 'ab:cd:ef:12:34:56',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier]).to eq('ab:cd:ef:12:34:56')
    end

    it 'accepts uppercase hex digits' do
      resource = described_class.new(
        name: 'upper-mac',
        identifier_type: 'hw-address',
        identifier: 'AB:CD:EF:12:34:56',
        ip_address: '192.0.2.100',
      )
      expect(resource[:identifier]).to eq('AB:CD:EF:12:34:56')
    end

    it 'rejects MAC addresses with invalid hex digits' do
      expect {
        described_class.new(
          name: 'bad-hex',
          identifier_type: 'hw-address',
          identifier: '01-a2-bb-cc-dh-ee-ff',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid MAC address format})
    end

    it 'rejects MAC addresses that are too short' do
      expect {
        described_class.new(
          name: 'short-mac',
          identifier_type: 'hw-address',
          identifier: '01-a2',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid MAC address format})
    end

    it 'rejects MAC addresses without proper separators' do
      expect {
        described_class.new(
          name: 'no-sep',
          identifier_type: 'hw-address',
          identifier: '01aabbccddeeff',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid MAC address format})
    end

    it 'rejects MAC addresses with mixed separators' do
      expect {
        described_class.new(
          name: 'mixed-sep',
          identifier_type: 'hw-address',
          identifier: '01:aa-bb:cc-dd:ee',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid MAC address format})
    end

    it 'rejects empty identifiers' do
      expect {
        described_class.new(
          name: 'empty',
          identifier_type: 'hw-address',
          identifier: '',
          ip_address: '192.0.2.100',
        )
      }.to raise_error(Puppet::ResourceError, %r{Identifier must be provided})
    end
  end

  context 'when validating IP addresses' do
    it 'rejects invalid IPv4 addresses' do
      expect {
        described_class.new(
          name: 'bad-ip',
          identifier_type: 'hw-address',
          identifier: '01:aa:bb:cc:dd:ee:ff',
          ip_address: 'not-an-ip',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid IPv4 address})
    end

    it 'rejects IPv4 addresses with octets > 255' do
      expect {
        described_class.new(
          name: 'high-octet',
          identifier_type: 'hw-address',
          identifier: '01:aa:bb:cc:dd:ee:ff',
          ip_address: '192.0.2.256',
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid IPv4 address})
    end

    it 'accepts valid IPv4 addresses' do
      resource = described_class.new(
        name: 'good-ip',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '10.20.30.40',
      )
      expect(resource[:ip_address]).to eq('10.20.30.40')
    end
  end

  context 'when validating scope_id' do
    it 'accepts integer scope_id values' do
      resource = described_class.new(
        name: 'with-scope',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
        scope_id: 123,
      )
      expect(resource[:scope_id]).to eq(123)
    end

    it 'accepts string integer scope_id values' do
      resource = described_class.new(
        name: 'with-scope-str',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
        scope_id: '456',
      )
      expect(resource[:scope_id]).to eq(456)
    end

    it 'accepts :auto for scope_id' do
      resource = described_class.new(
        name: 'auto-scope',
        identifier_type: 'hw-address',
        identifier: '01:aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.100',
        scope_id: :auto,
      )
      expect(resource[:scope_id]).to eq(:auto)
    end

    it 'rejects non-integer scope_id values' do
      expect {
        described_class.new(
          name: 'bad-scope',
          identifier_type: 'hw-address',
          identifier: '01:aa:bb:cc:dd:ee:ff',
          ip_address: '192.0.2.100',
          scope_id: 'not-a-number',
        )
      }.to raise_error(Puppet::ResourceError, %r{must be an integer})
    end
  end
end
