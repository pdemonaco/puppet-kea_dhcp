# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_ddns_server) do
  it 'only allows the dhcp-ddns instance name' do
    expect {
      described_class.new(name: 'default')
    }.to raise_error(Puppet::ResourceError, %r{Only the 'dhcp-ddns'})
  end

  it 'accepts valid configuration' do
    resource = described_class.new(
      name: 'dhcp-ddns',
      ip_address: '192.168.1.10',
      port: 53_001,
      tsig_keys: [{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'LSWXnfkKZjdPJI5QxlpnfQ==' }],
    )

    expect(resource[:ip_address]).to eq('192.168.1.10')
    expect(resource[:port]).to eq(53_001)
    expect(resource[:tsig_keys]).to eq([{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'LSWXnfkKZjdPJI5QxlpnfQ==' }])
  end

  describe 'ip_address property' do
    it 'accepts valid IPv4 addresses' do
      resource = described_class.new(name: 'dhcp-ddns', ip_address: '127.0.0.1')
      expect(resource[:ip_address]).to eq('127.0.0.1')
    end

    it 'accepts valid IPv6 addresses' do
      resource = described_class.new(name: 'dhcp-ddns', ip_address: '::1')
      expect(resource[:ip_address]).to eq('::1')
    end

    it 'rejects invalid IP addresses' do
      expect {
        described_class.new(name: 'dhcp-ddns', ip_address: 'not-an-ip')
      }.to raise_error(Puppet::ResourceError, %r{must be a valid IPv4 or IPv6 address})
    end

    it 'defaults to 127.0.0.1' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:ip_address]).to eq('127.0.0.1')
    end
  end

  describe 'port property' do
    it 'accepts valid ports' do
      resource = described_class.new(name: 'dhcp-ddns', port: 8080)
      expect(resource[:port]).to eq(8080)
    end

    it 'rejects ports outside valid range' do
      expect {
        described_class.new(name: 'dhcp-ddns', port: 70_000)
      }.to raise_error(Puppet::ResourceError, %r{must be between 1 and 65535})
    end

    it 'rejects non-integer ports' do
      expect {
        described_class.new(name: 'dhcp-ddns', port: 'not-a-number')
      }.to raise_error(Puppet::ResourceError, %r{must be an integer})
    end

    it 'defaults to 53001' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:port]).to eq(53_001)
    end
  end

  describe 'dns_server_timeout property' do
    it 'accepts valid timeouts' do
      resource = described_class.new(name: 'dhcp-ddns', dns_server_timeout: 1000)
      expect(resource[:dns_server_timeout]).to eq(1000)
    end

    it 'rejects negative timeouts' do
      expect {
        described_class.new(name: 'dhcp-ddns', dns_server_timeout: -1)
      }.to raise_error(Puppet::ResourceError, %r{must be positive})
    end

    it 'defaults to 500' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:dns_server_timeout]).to eq(500)
    end
  end

  describe 'ncr_protocol property' do
    it 'accepts UDP' do
      resource = described_class.new(name: 'dhcp-ddns', ncr_protocol: 'UDP')
      expect(resource[:ncr_protocol]).to eq('UDP')
    end

    it 'accepts TCP' do
      resource = described_class.new(name: 'dhcp-ddns', ncr_protocol: 'TCP')
      expect(resource[:ncr_protocol]).to eq('TCP')
    end

    it 'rejects invalid protocols' do
      expect {
        described_class.new(name: 'dhcp-ddns', ncr_protocol: 'HTTP')
      }.to raise_error(Puppet::ResourceError, %r{must be one of: UDP, TCP})
    end

    it 'defaults to UDP' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:ncr_protocol]).to eq('UDP')
    end
  end

  describe 'tsig_keys property' do
    let(:valid_key) do
      {
        'name' => 'foo',
        'algorithm' => 'HMAC-MD5',
        'secret' => 'LSWXnfkKZjdPJI5QxlpnfQ==',
      }
    end

    it 'accepts valid TSIG keys' do
      resource = described_class.new(name: 'dhcp-ddns', tsig_keys: [valid_key])
      expect(resource[:tsig_keys]).to eq([valid_key])
    end

    it 'rejects TSIG keys missing name' do
      invalid_key = valid_key.reject { |k, _| k == 'name' }
      expect {
        described_class.new(name: 'dhcp-ddns', tsig_keys: [invalid_key])
      }.to raise_error(Puppet::ResourceError, %r{TSIG key must contain name})
    end

    it 'rejects TSIG keys with invalid algorithms' do
      invalid_key = valid_key.merge('algorithm' => 'INVALID')
      expect {
        described_class.new(name: 'dhcp-ddns', tsig_keys: [invalid_key])
      }.to raise_error(Puppet::ResourceError, %r{algorithm must be one of})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp-ddns',
        tsig_keys: [{ name: 'foo', algorithm: 'HMAC-SHA256', secret: 'abc123==' }],
      )
      expect(resource[:tsig_keys]).to eq([{ 'name' => 'foo', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc123==' }])
    end

    it 'unwraps sensitive secrets' do
      sensitive_secret = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret-value')
      resource = described_class.new(
        name: 'dhcp-ddns',
        tsig_keys: [{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => sensitive_secret }],
      )
      expect(resource[:tsig_keys]).to eq([{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'secret-value' }])
    end

    it 'defaults to an empty array' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:tsig_keys]).to eq([])
    end
  end

  describe 'config_path parameter' do
    it 'defaults to /etc/kea/kea-dhcp-ddns.conf' do
      resource = described_class.new(name: 'dhcp-ddns')
      expect(resource[:config_path]).to eq('/etc/kea/kea-dhcp-ddns.conf')
    end

    it 'accepts a custom path' do
      resource = described_class.new(name: 'dhcp-ddns', config_path: '/custom/kea-ddns.conf')
      expect(resource[:config_path]).to eq('/custom/kea-ddns.conf')
    end
  end

  describe 'autorequire' do
    it 'autorequires the config file' do
      catalog = Puppet::Resource::Catalog.new
      config_file = Puppet::Type.type(:file).new(name: '/etc/kea/kea-dhcp-ddns.conf', ensure: :file)
      server = described_class.new(name: 'dhcp-ddns')
      catalog.add_resource(config_file)
      catalog.add_resource(server)

      relationship = server.autorequire[0]

      expect(relationship.source).to eq(config_file)
      expect(relationship.target).to eq(server)
    end
  end
end
