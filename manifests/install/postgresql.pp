# @summary Manages the PostgreSQL configuration for Kea DHCP
#
# @param database_name
#   The name of the PostgreSQL database to create for Kea DHCP.
# @param database_user
#   The PostgreSQL user to create for Kea DHCP.
# @param instance_user
#   The OS user that owns the PostgreSQL instance. Sourced from hiera.
# @param instance_group
#   The OS group that owns the PostgreSQL instance. Sourced from hiera.
# @param instance_directory_root
#   The root directory for the PostgreSQL instance directories. Sourced from hiera.
# @param lease_sensitive_db_password
#   The password for the PostgreSQL lease database user, wrapped in a Sensitive type.
# @param manage_package_repo
#   Whether to manage the PostgreSQL package repository.
# @param instance_port
#   The port number for the PostgreSQL instance to listen on.
# @param instance_host
#   Hostname or IP address used to connect to the PostgreSQL instance for schema
#   initialization and health checks. Must match the TCP listen address of the
#   PostgreSQL server. Defaults to 127.0.0.1.
# @param install_mode
#   Controls how the database is installed:
#   - 'instance': Create a dedicated PostgreSQL instance
#   - 'database': Add the Kea database to the existing default instance
class kea_dhcp::install::postgresql (
  String $instance_user,
  String $instance_group,
  Stdlib::Absolutepath $instance_directory_root,
  String $database_name = $kea_dhcp::lease_database_name,
  String $database_user = $kea_dhcp::lease_database_user,
  Sensitive[String] $lease_sensitive_db_password = $kea_dhcp::lease_sensitive_db_password,
  Boolean $manage_package_repo = true,
  Stdlib::Host $instance_host = '127.0.0.1',
  Stdlib::Port $instance_port = $kea_dhcp::lease_database_port,
  Kea_Dhcp::Db_install_mode $install_mode = $kea_dhcp::install::install_mode,
) {
  include 'postgresql::server'

  $plain_db_password = $lease_sensitive_db_password.unwrap
  $kea_unless = @("CMD"/L)
    /usr/bin/psql -h ${instance_host} -p ${instance_port} -U ${database_user} \
    -d ${database_name} -tAc "SELECT 1 FROM schema_version;" 2>/dev/null | \
    /usr/bin/grep -q 1
    |-CMD

  if $install_mode == 'instance' {
    $instance_name = $database_user
    $service_name = "postgresql@${instance_name}"
    $instance_data_dir = "${instance_directory_root}/data/${instance_name}"
    $instance_log_dir = "${instance_directory_root}/log/${instance_name}"

    postgresql::server_instance { $instance_name:
      instance_user               => $instance_user,
      instance_group              => $instance_group,
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
        group   => $instance_group,
        user    => $instance_user,
      },
    }

    postgresql::server::db { $database_name:
      user     => $database_user,
      password => $lease_sensitive_db_password,
      instance => $instance_name,
      port     => $instance_port,
      require  => Postgresql::Server_instance[$instance_name],
    }
  } else {
    # database mode: add to the existing default PostgreSQL instance
    postgresql::server::db { $database_name:
      user     => $database_user,
      password => $lease_sensitive_db_password,
      port     => $instance_port,
    }
  }

  exec { 'init_kea_dhcp_schema':
    command     => "/usr/sbin/kea-admin db-init pgsql -u ${database_user} -p \"\${PGPASSWORD}\" -h ${instance_host} -P ${instance_port} -n ${database_name}",
    unless      => $kea_unless,
    path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    environment => ["PGPASSWORD=${plain_db_password}"],
    user        => $instance_user,
    require     => Postgresql::Server::Db[$database_name],
    cwd         => '/tmp',
  }
}
