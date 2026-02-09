# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_ddns_domain) do
  it 'accepts valid configuration' do
    resource = described_class.new(
      name: 'example_domain',
      domain_name: 'example.com.',
      direction: 'forward',
      dns_servers: [{ 'ip-address' => '192.168.1.10', 'port' => 53 }],
    )

    expect(resource[:domain_name]).to eq('example.com.')
    expect(resource[:direction]).to eq('forward')
    expect(resource[:dns_servers]).to eq([{ 'ip-address' => '192.168.1.10', 'port' => 53 }])
  end

  describe 'domain_name property' do
    it 'accepts valid domain names' do
      resource = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      expect(resource[:domain_name]).to eq('example.com.')
    end

    it 'accepts reverse domain names' do
      resource = described_class.new(
        name: 'test',
        domain_name: '1.168.192.in-addr.arpa.',
        direction: 'reverse',
      )
      expect(resource[:domain_name]).to eq('1.168.192.in-addr.arpa.')
    end

    it 'rejects empty domain names' do
      expect {
        described_class.new(name: 'test', domain_name: '', direction: 'forward')
      }.to raise_error(Puppet::ResourceError, %r{cannot be empty})
    end
  end

  describe 'direction property' do
    it 'accepts forward' do
      resource = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      expect(resource[:direction]).to eq('forward')
    end

    it 'accepts reverse' do
      resource = described_class.new(name: 'test', domain_name: '1.168.192.in-addr.arpa.', direction: 'reverse')
      expect(resource[:direction]).to eq('reverse')
    end

    it 'rejects invalid directions' do
      expect {
        described_class.new(name: 'test', domain_name: 'example.com.', direction: 'invalid')
      }.to raise_error(Puppet::ResourceError, %r{must be one of: forward, reverse})
    end
  end

  describe 'key_name property' do
    it 'accepts valid key names' do
      resource = described_class.new(
        name: 'test',
        domain_name: 'example.com.',
        direction: 'forward',
        key_name: 'my-tsig-key',
      )
      expect(resource[:key_name]).to eq('my-tsig-key')
    end

    it 'rejects non-string key names' do
      expect {
        described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward', key_name: 123)
      }.to raise_error(Puppet::ResourceError, %r{must be a string})
    end
  end

  describe 'dns_servers property' do
    it 'accepts valid DNS server configurations' do
      servers = [
        { 'ip-address' => '192.168.1.10', 'port' => 53 },
        { 'ip-address' => '192.168.1.11', 'port' => 53, 'key-name' => 'foo' },
      ]
      resource = described_class.new(
        name: 'test',
        domain_name: 'example.com.',
        direction: 'forward',
        dns_servers: servers,
      )
      expect(resource[:dns_servers]).to eq(servers)
    end

    it 'rejects DNS servers without ip-address' do
      expect {
        described_class.new(
          name: 'test',
          domain_name: 'example.com.',
          direction: 'forward',
          dns_servers: [{ 'port' => 53 }],
        )
      }.to raise_error(Puppet::ResourceError, %r{must contain ip-address})
    end

    it 'rejects DNS servers with invalid IP addresses' do
      expect {
        described_class.new(
          name: 'test',
          domain_name: 'example.com.',
          direction: 'forward',
          dns_servers: [{ 'ip-address' => 'not-an-ip' }],
        )
      }.to raise_error(Puppet::ResourceError, %r{must be a valid IPv4 or IPv6 address})
    end

    it 'rejects DNS servers with invalid ports' do
      expect {
        described_class.new(
          name: 'test',
          domain_name: 'example.com.',
          direction: 'forward',
          dns_servers: [{ 'ip-address' => '192.168.1.10', 'port' => 70_000 }],
        )
      }.to raise_error(Puppet::ResourceError, %r{port must be between 1 and 65535})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'test',
        domain_name: 'example.com.',
        direction: 'forward',
        dns_servers: [{ 'ip-address': '192.168.1.10', port: 53 }],
      )
      expect(resource[:dns_servers]).to eq([{ 'ip-address' => '192.168.1.10', 'port' => 53 }])
    end

    it 'defaults to an empty array' do
      resource = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      expect(resource[:dns_servers]).to eq([])
    end
  end

  describe 'config_path parameter' do
    it 'defaults to /etc/kea/kea-dhcp-ddns.conf' do
      resource = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      expect(resource[:config_path]).to eq('/etc/kea/kea-dhcp-ddns.conf')
    end

    it 'accepts a custom path' do
      resource = described_class.new(
        name: 'test',
        domain_name: 'example.com.',
        direction: 'forward',
        config_path: '/custom/kea-ddns.conf',
      )
      expect(resource[:config_path]).to eq('/custom/kea-ddns.conf')
    end
  end

  describe 'autorequire' do
    it 'autorequires the config file' do
      catalog = Puppet::Resource::Catalog.new
      config_file = Puppet::Type.type(:file).new(name: '/etc/kea/kea-dhcp-ddns.conf', ensure: :file)
      domain = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      catalog.add_resource(config_file)
      catalog.add_resource(domain)

      relationships = domain.autorequire
      file_relationship = relationships.find { |r| r.source == config_file }

      expect(file_relationship).not_to be_nil
      expect(file_relationship.target).to eq(domain)
    end

    it 'autorequires the kea_ddns_server resource' do
      catalog = Puppet::Resource::Catalog.new
      server = Puppet::Type.type(:kea_ddns_server).new(name: 'dhcp-ddns')
      domain = described_class.new(name: 'test', domain_name: 'example.com.', direction: 'forward')
      catalog.add_resource(server)
      catalog.add_resource(domain)

      relationships = domain.autorequire
      server_relationship = relationships.find { |r| r.source == server }

      expect(server_relationship).not_to be_nil
      expect(server_relationship.target).to eq(domain)
    end
  end
end
