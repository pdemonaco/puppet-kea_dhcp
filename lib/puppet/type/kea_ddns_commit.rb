# frozen_string_literal: true

Puppet::Type.newtype(:kea_ddns_commit) do
  @doc = 'Commits staged Kea DHCP-DDNS configuration changes to disk.'

  newparam(:name, namevar: true) do
    desc 'Path to the kea-dhcp-ddns configuration file being committed.'
  end

  newproperty(:applied) do
    desc 'Whether staged changes have been applied. Managed automatically.'
    defaultto 'committed'

    def insync?(is)
      is == 'committed'
    end
  end

  autorequire(:kea_ddns_server) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_ddns_server)) }
  end

  autorequire(:kea_ddns_domain) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_ddns_domain)) }
  end
end
