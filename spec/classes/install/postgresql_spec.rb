# Frozen_string_literal: true

require 'spec_helper'
require 'deep_merge'

describe 'kea_dhcp::install::postgresql' do
  let(:facts) do
    rocky_facts = on_supported_os['rocky-9-x86_64'] ||
                  on_supported_os['redhat-9-x86_64'] ||
                  on_supported_os.values.first ||
                  {}

    resolved_facts = Marshal.load(Marshal.dump(rocky_facts))

    os_fact = resolved_facts['os'] || resolved_facts[:os]
    structured_os = os_fact.is_a?(Hash) ? os_fact.dup : {}

    os_name = 'Rocky'
    os_family = resolved_facts['osfamily'] || resolved_facts[:osfamily] || 'RedHat'
    os_release_full = resolved_facts['operatingsystemrelease'] || resolved_facts[:operatingsystemrelease]
    os_release_major = resolved_facts['operatingsystemmajrelease'] || resolved_facts[:operatingsystemmajrelease]
    os_release_major ||= os_release_full&.split('.')&.first

    structured_os['name'] ||= os_name
    structured_os['family'] ||= os_family if os_family
    structured_os['release'] ||= {}
    structured_os['release']['full'] ||= os_release_full if os_release_full
    structured_os['release']['major'] ||= os_release_major if os_release_major
    structured_os.delete('release') if structured_os['release'].empty?

    resolved_facts['operatingsystem'] ||= os_name
    resolved_facts[:operatingsystem] ||= os_name
    resolved_facts['os'] = structured_os
    resolved_facts[:os] = structured_os

    resolved_facts
  end
  let(:pre_condition) { 'include postgresql::server' }
  let(:database_name) { 'kea' }
  let(:database_user) { 'kea' }
  let(:instance_directory_root) { '/opt/pgsql' }
  let(:instance_port) { 5432 }
  let(:plain_password) { 'supersecret' }
  let(:params) do
    {
      database_name: database_name,
      database_user: database_user,
      instance_directory_root: instance_directory_root,
      instance_port: instance_port,
      sensitive_db_password: RSpec::Puppet::RawString.new('Sensitive("supersecret")'),
    }
  end

  let(:instance_data_dir) { "#{instance_directory_root}/data/#{database_user}" }
  let(:instance_log_dir) { "#{instance_directory_root}/log/#{database_user}" }
  let(:service_name) { "postgresql@#{database_user}" }

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_class('postgresql::server') }

  it do
    is_expected.to contain_postgresql__server_instance(database_user).with(
      'instance_user' => 'postgres',
      'instance_group' => 'postgres',
      'instance_directories' => {
        instance_directory_root => { 'ensure' => 'directory' },
        "#{instance_directory_root}/backup" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/data" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/wal" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/log" => { 'ensure' => 'directory' },
        instance_log_dir => { 'ensure' => 'directory' },
      },
      'instance_user_homedirectory' => "#{instance_directory_root}/data/home",
      'config_settings' => {
        'pg_hba_conf_path' => "#{instance_data_dir}/pg_hba.conf",
        'postgresql_conf_path' => "#{instance_data_dir}/postgresql.conf",
        'pg_ident_conf_path' => "#{instance_data_dir}/pg_ident.conf",
        'datadir' => instance_data_dir,
        'service_name' => service_name,
        'port' => instance_port,
      },
      'service_settings' => {
        'service_name' => service_name,
        'service_status' => "systemctl status #{service_name}.service",
        'service_enable' => true,
        'service_ensure' => 'running',
      },
      'initdb_settings' => {
        'datadir' => instance_data_dir,
        'group' => 'postgres',
        'user' => 'postgres',
      },
    )
  end

  it do
    is_expected.to contain_postgresql__server__db(database_name).with(
      'user' => database_user,
      'password' => 'Sensitive("supersecret")',
      'instance' => database_user,
      'require' => "Postgresql::Server_instance[#{database_user}]",
    )
  end

  it do
    unless_cmd = "/usr/bin/psql -p #{instance_port} -d #{database_name} " \
                 '-tAc "SELECT 1 FROM schema_version;" | /usr/bin/grep -q 1'
    is_expected.to contain_exec('init_kea_dhcp_schema').with(
      'command' => "/usr/sbin/kea-admin db-init pgsql -u #{database_user} -p \"\${PGPASSWORD}\" -h 127.0.0.1 -P #{instance_port} -n #{database_name}",
      'unless' => unless_cmd,
      'path' => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      'user' => 'postgres',
    ).that_requires("Postgresql::Server::Db[#{database_name}]")
  end
end
