import Config

config :dns_server,
  udp_truncate_length: 512,
  message_max_label_length: 63,
  message_max_name_length: 255,
  cache_table_name: :dns_server_cache,
  master_table_name: :dns_server_master,
  foreign_name_servers: [
    # Cloudflare
    {{1, 1, 1, 1}, 53},
    # Google
    {{8, 8, 8, 8}, 53},
    # Google
    {{8, 8, 4, 4}, 53},
    # OpenDNS
    {{208, 67, 220, 220}, 53}
  ]
