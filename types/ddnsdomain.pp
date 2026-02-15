# @summary Utility type for declaring DDNS domains
#
# @param name
#   Unique Puppet identifier for this DDNS domain
#
# @param domain_name
#   The DNS domain name (e.g., 'example.com.' or '1.168.192.in-addr.arpa.')
#
# @param direction
#   The direction of this domain: 'forward' for forward DNS or 'reverse' for reverse DNS
#
# @param key_name
#   Optional TSIG key name to use for all DNS servers in this domain (unless overridden per-server)
#
# @param dns_servers
#   Optional array of DNS server configurations. Each server is a hash containing:
#     - 'ip-address' (required): IPv4 or IPv6 address of the DNS server
#     - 'port' (optional): Port number (1-65535, defaults to 53)
#     - 'key-name' (optional): TSIG key name for this specific server
type Kea_Dhcp::DdnsDomain = Struct[
  name                   => String,
  domain_name            => String[1],
  direction              => Enum['forward', 'reverse'],
  Optional[key_name]     => String,
  Optional[dns_servers]  => Array[Struct[{
        'ip-address'           => Stdlib::IP::Address,
        Optional['port']       => Integer[1, 65535],
        Optional['key-name']   => String,
  }]],
]
