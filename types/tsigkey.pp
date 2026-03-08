# @summary Type alias for TSIG key configurations used by Kea DDNS
#
# Supports two variants:
# - secret: the TSIG key value is provided directly, optionally wrapped in Sensitive
# - secret-file: the key value is written to a file managed by this module;
#   provide the file content via the secret_file_content field
type Kea_Dhcp::TsigKey = Variant[
  Struct[
    name      => String[1],
    algorithm => Enum['HMAC-MD5', 'HMAC-SHA1', 'HMAC-SHA224', 'HMAC-SHA256', 'HMAC-SHA384', 'HMAC-SHA512'],
    secret    => Variant[String[1], Sensitive[String[1]]],
  ],
  Struct[
    name                => String[1],
    algorithm           => Enum['HMAC-MD5', 'HMAC-SHA1', 'HMAC-SHA224', 'HMAC-SHA256', 'HMAC-SHA384', 'HMAC-SHA512'],
    secret_file_content => Variant[String[1], Sensitive[String[1]]],
  ],
]
