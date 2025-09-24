require 'spec_helper'

describe 'kea_dhcp::install::postgresql' do
  let(:database_name) { 'kea_dhcp' }
  let(:database_user) { 'kea' }
  let(:instance_directory_root) { '/opt/pgsql' }
  let(:sensitive_password) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('supersecret') }
  let(:plain_password) { sensitive_password.unwrap }
  let(:params) do
    {
      database_name: database_name,
      database_user: database_user,
      instance_directory_root: instance_directory_root,
      sensitive_db_password: sensitive_password,
    }
  end

  let(:instance_data_dir) { "#{instance_directory_root}/data/16/#{database_user}" }
  let(:instance_log_dir) { "#{instance_directory_root}/log/16/#{database_user}" }
  let(:postgresql_service_name) { "postgresql-16-#{database_user}" }
  let(:systemd_service_name) { "postgresql@16-#{database_user}" }

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_class('postgresql::server') }

  it do
    is_expected.to contain_class('postgresql::globals').with(
      'manage_package_repo' => true,
      'version' => '16',
    )
  end

  it do
    is_expected.to contain_postgresql__server_instance(database_user).with(
      'ensure' => 'present',
      'instance_user' => 'postgres',
      'instance_group' => 'postgres',
      'instance_directories' => {
        instance_directory_root => { 'ensure' => 'directory' },
        "#{instance_directory_root}/backup" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/data" => { 'ensure' => 'directory' },
        instance_data_dir => { 'ensure' => 'directory' },
        "#{instance_directory_root}/data/home" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/wal" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/log" => { 'ensure' => 'directory' },
        "#{instance_directory_root}/log/16" => { 'ensure' => 'directory' },
        instance_log_dir => { 'ensure' => 'directory' },
      },
      'config_settings' => {
        'pg_hba_conf_path' => "#{instance_data_dir}/pg_hba.conf",
        'postgresql_conf_path' => "#{instance_data_dir}/postgresql.conf",
        'pg_ident_conf_path' => "#{instance_data_dir}/pg_ident.conf",
        'datadir' => instance_data_dir,
        'service_name' => postgresql_service_name,
        'port' => '5433',
      },
      'service_settings' => {
        'service_name' => systemd_service_name,
        'service_status' => "systemctl status #{systemd_service_name}.service",
        'service_enable' => true,
        'service_ensure' => 'running',
      },
      'inidb_settings' => {
        'datadir' => instance_data_dir,
        'group' => 'postgres',
        'user' => 'postgres',
      },
    )
  end

  it do
    is_expected.to contain_postgresql__server__db(database_name).with(
      'user' => database_user,
      'password' => sensitive_password,
      'instance' => database_user,
      'require' => "Postgresql::Server_instance[#{database_user}]",
    )
  end

  it do
    is_expected.to contain_exec('init_kea_dhcp_schema').with(
      'command' => "/usr/sbin/kea-admin db-init pgsql -u #{database_user} -p \"#{plain_password}\" -h 127.0.0.1 -P 5433 -n #{database_name}",
      'unless' => "/usr/bin/psql -tAc \"SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_version';\" '#{database_name}' | /usr/bin/grep -q 1",
      'path' => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      'user' => 'postgres',
      'require' => "Postgresql::Server::Db[#{database_name}]",
    )
  end
end
