# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp class on Rocky 9' do
  let(:db_password) { 'LitmusP@ssw0rd!' }
  let(:manifest) do
    <<~PP
      class { 'kea_dhcp':
        sensitive_db_password       => Sensitive('#{db_password}'),
        array_dhcp4_server_options  => [
          { 'name' => 'routers', 'data' => '192.0.2.1' },
        ],
        enable_ddns                 => false,
        enable_ctrl_agent           => false,
      }
    PP
  end
  let(:pre) do
    <<~PP
      yumrepo { 'isc-kea-3-0':
        ensure          => present,
        descr           => 'ISC - kea-3-0',
        baseurl         => 'https://dl.cloudsmith.io/public/isc/kea-3-0/rpm/el/$releasever/$basearch',
        enabled         => 1,
        gpgcheck        => 1,
        repo_gpgcheck   => 1,
        gpgkey          => 'https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.9C7DE5B4B1F07C3F.key',
        sslverify       => 1,
        sslcacert       => '/etc/pki/tls/certs/ca-bundle.crt',
        metadata_expire => 300,
      }

      yumrepo { 'PGDG-common':
        ensure  => present,
        descr   => 'PostgreSQL common repository',
        baseurl => 'https://download.postgresql.org/pub/repos/yum/common/redhat/rhel-$releasever-$basearch',
        enabled => 1,
        gpgcheck => 1,
        gpgkey  => 'https://download.postgresql.org/pub/repos/yum/RPM-GPG-KEY-PGDG',
      }

      yumrepo { 'PGDG-16':
        ensure  => present,
        descr   => 'PostgreSQL 16 for RHEL $releasever - $basearch',
        baseurl => 'https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$releasever-$basearch',
        enabled => 1,
        gpgcheck => 1,
        gpgkey  => 'https://download.postgresql.org/pub/repos/yum/RPM-GPG-KEY-PGDG',
      }
    PP
  end

  it 'applies the manifest idempotently' do
    manifest_path = '/tmp/kea_dhcp.pp'
    pre_manifest_path = '/tmp/kea_dhcp_pre.pp'
    command = <<~SHELL
      cat <<'PP' > #{pre_manifest_path}
      #{pre}
      PP
      puppet apply #{pre_manifest_path} --detailed-exitcodes
      pre_run=$?
      if [ $pre_run -ne 0 ] && [ $pre_run -ne 2 ]; then
        exit $pre_run
      fi
      cat <<'PP' > #{manifest_path}
      #{manifest}
      PP
      puppet apply #{manifest_path} --detailed-exitcodes
      first_run=$?
      if [ $first_run -ne 0 ] && [ $first_run -ne 2 ]; then
        exit $first_run
      fi
      puppet apply #{manifest_path} --detailed-exitcodes
      second_run=$?
      if [ $second_run -ne 0 ]; then
        exit $second_run
      fi
      rm -f #{manifest_path} #{pre_manifest_path}
      exit 0
    SHELL

    result = run_shell(command)
    expect(result.exit_code).to eq(0)
  end

  describe package('isc-kea') do
    it { is_expected.to be_installed }

    it 'installs kea 3.0.x' do
      version = run_shell("rpm -q --qf '%{VERSION}' isc-kea").stdout.strip
      expect(version).to match(/\A3\.0\./)
    end
  end

  it 'creates the PostgreSQL database for leases' do
    query = "SELECT 1 FROM pg_database WHERE datname = 'kea_dhcp';"
    result = run_shell("su - postgres -c \"psql -tAc \\\"#{query}\\\"\"")
    expect(result.stdout).to match(/1/)
  end

  it 'starts the required services' do
    %w[kea-dhcp4 postgresql@16-kea].each do |svc|
      status = run_shell("systemctl is-active #{svc}", expect_failures: false)
      expect(status.stdout.strip).to eq('active')
    end
  end

  it 'creates the kea-dhcp4 configuration with the expected lease database' do
    config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
    dhcp4 = config.fetch('Dhcp4')
    lease_db = dhcp4.fetch('lease-database')

    expect(lease_db['name']).to eq('kea_dhcp')
    expect(lease_db['user']).to eq('kea')
    expect(lease_db['port']).to eq(5433)

    server_options = Array(dhcp4['option-data'])
    router_option = server_options.find { |opt| opt['name'] == 'routers' }
    expect(router_option).not_to be_nil
    expect(router_option['data']).to eq('192.0.2.1')
  end
end
