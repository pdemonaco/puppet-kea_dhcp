# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:kea_dhcp_v4_server) do
  let(:base_lease_db) do
    {
      'type' => 'postgresql',
      'name' => 'kea_dhcp',
      'user' => 'kea',
      'password' => Puppet::Pops::Types::PSensitiveType::Sensitive.new('kea_password'),
      'host' => '127.0.0.1',
      'port' => 5433,
    }
  end

  it 'only allows the dhcp4 instance name' do
    expect {
      described_class.new(name: 'default', lease_database: base_lease_db)
    }.to raise_error(Puppet::ResourceError, %r{Only the 'dhcp4'})
  end

  it 'accepts valid configuration' do
    resource = described_class.new(
      name: 'dhcp4',
      lease_database: base_lease_db.merge('port' => '5433'),
      options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
    )

    expect(resource[:lease_database]['port']).to eq(5433)
    expect(resource[:lease_database]['password']).to eq('kea_password')
    expect(resource[:options]).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
  end

  it 'rejects invalid option entries' do
    expect {
      described_class.new(name: 'dhcp4', lease_database: base_lease_db, options: ['invalid'])
    }.to raise_error(Puppet::ResourceError, %r{Each option must be a hash})
  end

  it 'rejects lease databases without required keys' do
    expect {
      described_class.new(name: 'dhcp4', lease_database: { 'type' => 'postgresql' })
    }.to raise_error(Puppet::ResourceError, %r{Lease database name must be provided})
  end

  it 'rejects lease databases with unsupported backends' do
    expect {
      described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db.merge('type' => 'mysql'),
      )
    }.to raise_error(Puppet::ResourceError, %r{Only the postgresql})
  end

  it 'rejects non integer ports' do
    expect {
      described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db.merge('port' => 'not-a-number'),
      )
    }.to raise_error(Puppet::ResourceError, %r{Lease database port must be an integer})
  end

  describe 'options property' do
    it 'rejects options missing the name key' do
      expect {
        described_class.new(name: 'dhcp4', lease_database: base_lease_db, options: [{ 'data' => '10.0.0.1' }])
      }.to raise_error(Puppet::ResourceError, %r{Each option must be a hash containing at least name and data})
    end

    it 'rejects options missing the data key' do
      expect {
        described_class.new(name: 'dhcp4', lease_database: base_lease_db, options: [{ 'name' => 'routers' }])
      }.to raise_error(Puppet::ResourceError, %r{Each option must be a hash containing at least name and data})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        options: [{ name: 'routers', data: '10.0.0.1' }],
      )

      expect(resource[:options]).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
    end

    it 'defaults to an empty array' do
      resource = described_class.new(name: 'dhcp4', lease_database: base_lease_db)

      expect(resource[:options]).to eq([])
    end

    it 'unwraps sensitive values in option data' do
      sensitive_data = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret-value')
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        options: [{ 'name' => 'auth-key', 'data' => sensitive_data }],
      )

      expect(resource[:options]).to eq([{ 'name' => 'auth-key', 'data' => 'secret-value' }])
    end
  end

  describe 'hooks_libraries property' do
    it 'accepts valid hooks library configuration' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
      )

      expect(resource[:hooks_libraries]).to eq([{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }])
    end

    it 'rejects hooks libraries that are not hashes' do
      expect {
        described_class.new(name: 'dhcp4', lease_database: base_lease_db, hooks_libraries: ['invalid'])
      }.to raise_error(Puppet::ResourceError, %r{Each hooks library must be a hash containing at least a library key})
    end

    it 'rejects hooks libraries missing the library key' do
      expect {
        described_class.new(name: 'dhcp4', lease_database: base_lease_db, hooks_libraries: [{ 'parameters' => {} }])
      }.to raise_error(Puppet::ResourceError, %r{Each hooks library must be a hash containing at least a library key})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        hooks_libraries: [{ library: '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
      )

      expect(resource[:hooks_libraries]).to eq([{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }])
    end

    it 'converts nested symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        hooks_libraries: [{ library: '/usr/lib/kea/hooks/libdhcp_lease_cmds.so', parameters: { enabled: true } }],
      )

      expect(resource[:hooks_libraries]).to eq(
        [
          {
            'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so',
            'parameters' => { 'enabled' => true },
          },
        ],
      )
    end

    it 'defaults to an empty array' do
      resource = described_class.new(name: 'dhcp4', lease_database: base_lease_db)

      expect(resource[:hooks_libraries]).to eq([])
    end
  end

  describe 'lease_database property' do
    it 'rejects non-hash values' do
      expect {
        described_class.new(name: 'dhcp4', lease_database: 'invalid')
      }.to raise_error(Puppet::ResourceError, %r{Lease database must be provided as a hash})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: {
          type: 'postgresql',
          name: 'kea_dhcp',
          user: 'kea',
          password: 'secret',
          host: '127.0.0.1',
          port: 5433,
        },
      )

      expect(resource[:lease_database]).to eq({
                                                'type' => 'postgresql',
                                                'name' => 'kea_dhcp',
                                                'user' => 'kea',
                                                'password' => 'secret',
                                                'host' => '127.0.0.1',
                                                'port' => 5433,
                                              })
    end

    ['name', 'user', 'password', 'host', 'port'].each do |required_key|
      it "requires the #{required_key} key" do
        incomplete_db = base_lease_db.reject { |k, _| k == required_key }
        expect {
          described_class.new(name: 'dhcp4', lease_database: incomplete_db)
        }.to raise_error(Puppet::ResourceError, %r{Lease database #{required_key} must be provided})
      end
    end
  end

  describe 'config_path parameter' do
    it 'defaults to /etc/kea/kea-dhcp4.conf' do
      resource = described_class.new(name: 'dhcp4', lease_database: base_lease_db)

      expect(resource[:config_path]).to eq('/etc/kea/kea-dhcp4.conf')
    end

    it 'accepts a custom path' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        config_path: '/custom/path/kea-dhcp4.conf',
      )

      expect(resource[:config_path]).to eq('/custom/path/kea-dhcp4.conf')
    end
  end

  describe 'dhcp_ddns property' do
    it 'accepts valid DHCP-DDNS configuration' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        dhcp_ddns: {
          'enable-updates' => true,
          'server-ip' => '127.0.0.1',
          'server-port' => 53_001,
          'ncr-protocol' => 'UDP',
        },
      )

      expect(resource[:dhcp_ddns]).to eq({
                                           'enable-updates' => true,
                                           'server-ip' => '127.0.0.1',
                                           'server-port' => 53_001,
                                           'ncr-protocol' => 'UDP',
                                         })
    end

    it 'rejects invalid enable-updates values' do
      expect {
        described_class.new(
          name: 'dhcp4',
          lease_database: base_lease_db,
          dhcp_ddns: { 'enable-updates' => 'yes' },
        )
      }.to raise_error(Puppet::ResourceError, %r{enable-updates must be a boolean})
    end

    it 'rejects invalid server-port values' do
      expect {
        described_class.new(
          name: 'dhcp4',
          lease_database: base_lease_db,
          dhcp_ddns: { 'server-port' => 70_000 },
        )
      }.to raise_error(Puppet::ResourceError, %r{server-port must be between 1 and 65535})
    end

    it 'rejects invalid ncr-protocol values' do
      expect {
        described_class.new(
          name: 'dhcp4',
          lease_database: base_lease_db,
          dhcp_ddns: { 'ncr-protocol' => 'HTTP' },
        )
      }.to raise_error(Puppet::ResourceError, %r{ncr-protocol must be one of: UDP, TCP})
    end

    it 'rejects invalid ddns-replace-client-name values' do
      expect {
        described_class.new(
          name: 'dhcp4',
          lease_database: base_lease_db,
          dhcp_ddns: { 'ddns-replace-client-name' => 'invalid' },
        )
      }.to raise_error(Puppet::ResourceError, %r{ddns-replace-client-name must be one of})
    end

    it 'converts symbol keys to strings' do
      resource = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        dhcp_ddns: {
          'enable-updates': true,
          'server-ip': '127.0.0.1',
        },
      )

      expect(resource[:dhcp_ddns]).to eq({
                                           'enable-updates' => true,
                                           'server-ip' => '127.0.0.1',
                                         })
    end
  end

  describe 'autorequire' do
    it 'autorequires the config file' do
      catalog = Puppet::Resource::Catalog.new
      config_file = Puppet::Type.type(:file).new(name: '/etc/kea/kea-dhcp4.conf', ensure: :file)
      server = described_class.new(name: 'dhcp4', lease_database: base_lease_db)
      catalog.add_resource(config_file)
      catalog.add_resource(server)

      relationship = server.autorequire[0]

      expect(relationship.source).to eq(config_file)
      expect(relationship.target).to eq(server)
    end

    it 'autorequires a custom config file path' do
      catalog = Puppet::Resource::Catalog.new
      config_file = Puppet::Type.type(:file).new(name: '/custom/kea.conf', ensure: :file)
      server = described_class.new(
        name: 'dhcp4',
        lease_database: base_lease_db,
        config_path: '/custom/kea.conf',
      )
      catalog.add_resource(config_file)
      catalog.add_resource(server)

      relationship = server.autorequire[0]

      expect(relationship.source).to eq(config_file)
      expect(relationship.target).to eq(server)
    end
  end
end
