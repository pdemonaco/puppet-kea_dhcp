# @summary Manages the PostgreSQL configuration for Kea DHCP
#
# @param database_name
#   The name of the PostgreSQL database to create for Kea DHCP.
# @param database_user
#   The PostgreSQL user to create for Kea DHCP.
# @param instance_directory_root
#   The root directory for the PostgreSQL instance directories.
# @param sensitive_db_password
#   The password for the PostgreSQL user, wrapped in a Sensitive type.
# @param manage_package_repo
#   Whether to manage the PostgreSQL package repository.
class kea_dhcp::install::postgresql (
  String $database_name = 'kea',
  String $database_user = 'kea',
  Stdlib::Absolutepath $instance_directory_root = '/opt/pgsql',
  Sensitive[String] $sensitive_db_password = $kea_dhcp::sensitive_db_password,
  Boolean $manage_package_repo = true,
  Stdlib::Port $instance_port = 5433,
) {
  include 'postgresql::server'
  $instance_name = $database_user
  $service_name = "postgresql@${instance_name}"
  $instance_data_dir = "${instance_directory_root}/data/${instance_name}"
  $instance_log_dir = "${instance_directory_root}/log/${instance_name}"

  postgresql::server_instance { $instance_name:
    instance_user               => 'postgres',
    instance_group              => 'postgres',
    instance_directories        => {
      $instance_directory_root            => {
        ensure => directory,
      },
      "${instance_directory_root}/backup" => {
        ensure => directory,
      },
      "${instance_directory_root}/data"   => {
        ensure => directory,
      },
      "${instance_directory_root}/wal"    => {
        ensure => directory,
      },
      "${instance_directory_root}/log"    => {
        ensure => directory,
      },
      $instance_log_dir                   => {
        ensure => directory,
      },
    },
    instance_user_homedirectory => "${instance_directory_root}/data/home",
    config_settings             => {
      pg_hba_conf_path     => "${instance_data_dir}/pg_hba.conf",
      postgresql_conf_path => "${instance_data_dir}/postgresql.conf",
      pg_ident_conf_path   => "${instance_data_dir}/pg_ident.conf",
      datadir              => $instance_data_dir,
      service_name         => $service_name,
      port                 => $instance_port,
    },
    service_settings            => {
      service_name   => $service_name,
      service_status => "systemctl status ${service_name}.service",
      service_enable => true,
      service_ensure => 'running',
    },
    initdb_settings             => {
      datadir => $instance_data_dir,
      group   => 'postgres',
      user    => 'postgres',
    },
  }

  # Create the database
  postgresql::server::db { $database_name:
    user     => $database_user,
    password => $sensitive_db_password,
    instance => $instance_name,
    port     => $instance_port,
    require  => Postgresql::Server_instance[$instance_name],
  }

  $plain_db_password = $sensitive_db_password.unwrap
  $kea_unless = @("CMD"/L)
    /usr/bin/psql -tAc "SELECT 1 FROM information_schema.tables WHERE \
    table_schema = 'public' AND table_name = 'schema_version';" \
    '${database_name}' | /usr/bin/grep -q 1
    |-CMD

  exec { 'init_kea_dhcp_schema':
    command     => "/usr/sbin/kea-admin db-init pgsql -u ${database_user} -p \"\${PGPASSWORD}\" -h 127.0.0.1 -P ${instance_port} -n ${database_name}",
    unless      => $kea_unless,
    path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    environment => ["PGPASSWORD=${plain_db_password}"],
    user        => 'postgres',
    require     => Postgresql::Server::Db[$database_name],
  }
}
