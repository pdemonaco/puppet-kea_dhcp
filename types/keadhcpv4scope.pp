# @summary Utility type for declaring multiple scopes
type Kea_Dhcp::V4Scope = Struct[
  name              => String,
  subnet            => Stdlib::IP::Address::V4::CIDR,
  Optional[options] => Array[Hash],
  pools             => Array[String],
]
