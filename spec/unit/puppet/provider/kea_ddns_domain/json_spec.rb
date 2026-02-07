# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_ddns_domain).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_ddns_domain) }
  let(:tempfile) { Tempfile.new('kea-ddns-domain') }
  let(:config_path) { tempfile.path }

  before(:each) do
    tempfile.close
    provider_class.clear_state!
    allow(Puppet::Util::Execution).to receive(:execute).and_return('')
  end

  after(:each) do
    File.delete(config_path) if File.exist?(config_path)
  end

  def write_config(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end

  def read_config(path)
    JSON.parse(File.read(path))
  end

  context 'when creating forward domain' do
    it 'adds domain to forward-ddns section' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      resource = type_class.new(
        name: 'example_domain',
        config_path: config_path,
        domain_name: 'example.com.',
        direction: 'forward',
        dns_servers: [{ 'ip-address' => '192.168.1.10', 'port' => 53 }],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      forward_ddns = config['DhcpDdns']['forward-ddns']
      domains = forward_ddns['ddns-domains']

      expect(domains.length).to eq(1)
      expect(domains[0]['name']).to eq('example.com.')
      expect(domains[0]['user-context']['puppet_name']).to eq('example_domain')
      expect(domains[0]['dns-servers']).to contain_exactly({ 'ip-address' => '192.168.1.10', 'port' => 53 })
    end

    it 'adds domain with key-name' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      resource = type_class.new(
        name: 'secure_domain',
        config_path: config_path,
        domain_name: 'secure.example.com.',
        direction: 'forward',
        key_name: 'tsig-key-foo',
        dns_servers: [{ 'ip-address' => '192.168.1.10' }],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      domains = config['DhcpDdns']['forward-ddns']['ddns-domains']

      expect(domains[0]['key-name']).to eq('tsig-key-foo')
    end
  end

  context 'when creating reverse domain' do
    it 'adds domain to reverse-ddns section' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      resource = type_class.new(
        name: 'reverse_domain',
        config_path: config_path,
        domain_name: '1.168.192.in-addr.arpa.',
        direction: 'reverse',
        dns_servers: [{ 'ip-address' => '192.168.1.10', 'port' => 53 }],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      reverse_ddns = config['DhcpDdns']['reverse-ddns']
      domains = reverse_ddns['ddns-domains']

      expect(domains.length).to eq(1)
      expect(domains[0]['name']).to eq('1.168.192.in-addr.arpa.')
      expect(domains[0]['user-context']['puppet_name']).to eq('reverse_domain')
    end
  end

  context 'when updating domain' do
    it 'modifies existing domain configuration' do
      write_config(
        config_path,
        'DhcpDdns' => {
          'forward-ddns' => {
            'ddns-domains' => [
              {
                'name' => 'example.com.',
                'user-context' => { 'puppet_name' => 'example_domain' },
                'dns-servers' => [{ 'ip-address' => '192.168.1.10' }],
              },
            ],
          },
          'reverse-ddns' => {},
        },
      )

      resource = type_class.new(
        name: 'example_domain',
        config_path: config_path,
        domain_name: 'updated.example.com.',
        direction: 'forward',
        dns_servers: [{ 'ip-address' => '192.168.1.20', 'port' => 5353 }],
      )

      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      provider = provider_class.new(
        name: 'example_domain',
        domain_name: 'example.com.',
        direction: 'forward',
        dns_servers: [{ 'ip-address' => '192.168.1.10' }],
        config_path: config_path,
        ensure: :present,
      )
      provider.resource = resource
      resource.provider = provider

      provider.domain_name = 'updated.example.com.'
      provider.dns_servers = [{ 'ip-address' => '192.168.1.20', 'port' => 5353 }]
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      domains = config['DhcpDdns']['forward-ddns']['ddns-domains']

      expect(domains[0]['name']).to eq('updated.example.com.')
      expect(domains[0]['dns-servers']).to contain_exactly({ 'ip-address' => '192.168.1.20', 'port' => 5353 })
    end
  end

  context 'when destroying domain' do
    it 'removes domain from configuration' do
      write_config(
        config_path,
        'DhcpDdns' => {
          'forward-ddns' => {
            'ddns-domains' => [
              {
                'name' => 'example.com.',
                'user-context' => { 'puppet_name' => 'example_domain' },
                'dns-servers' => [{ 'ip-address' => '192.168.1.10' }],
              },
            ],
          },
          'reverse-ddns' => {},
        },
      )

      resource = type_class.new(
        name: 'example_domain',
        config_path: config_path,
        domain_name: 'example.com.',
        direction: 'forward',
        ensure: :absent,
      )

      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      provider = provider_class.new(
        name: 'example_domain',
        domain_name: 'example.com.',
        direction: 'forward',
        dns_servers: [{ 'ip-address' => '192.168.1.10' }],
        config_path: config_path,
        ensure: :present,
      )
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      domains = config['DhcpDdns']['forward-ddns']['ddns-domains']

      expect(domains).to be_empty
    end
  end

  context 'when discovering existing domains' do
    it 'finds both forward and reverse domains' do
      config = {
        'DhcpDdns' => {
          'forward-ddns' => {
            'ddns-domains' => [
              {
                'name' => 'example.com.',
                'user-context' => { 'puppet_name' => 'forward_domain' },
                'dns-servers' => [{ 'ip-address' => '192.168.1.10' }],
              },
            ],
          },
          'reverse-ddns' => {
            'ddns-domains' => [
              {
                'name' => '1.168.192.in-addr.arpa.',
                'user-context' => { 'puppet_name' => 'reverse_domain' },
                'dns-servers' => [{ 'ip-address' => '192.168.1.10' }],
              },
            ],
          },
        },
      }

      allow(provider_class).to receive(:config_for).and_return(config)

      instances = provider_class.instances

      expect(instances.length).to eq(2)
      forward = instances.find { |i| i.get(:name) == 'forward_domain' }
      reverse = instances.find { |i| i.get(:name) == 'reverse_domain' }

      expect(forward.get(:domain_name)).to eq('example.com.')
      expect(forward.get(:direction)).to eq('forward')
      expect(reverse.get(:domain_name)).to eq('1.168.192.in-addr.arpa.')
      expect(reverse.get(:direction)).to eq('reverse')
    end

    it 'returns empty array when no domains exist' do
      config = { 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} } }

      allow(provider_class).to receive(:config_for).and_return(config)

      instances = provider_class.instances

      expect(instances).to be_empty
    end
  end
end
