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
end
