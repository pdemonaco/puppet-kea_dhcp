# @summary Utility type for declaring DDNS domains
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
