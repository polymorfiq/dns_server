defmodule DnsServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias DnsServer.Listener.{Tcp, Udp}

  @cache_table Application.compile_env(:dns_server, :cache_table_name)
  @master_table Application.compile_env(:dns_server, :master_table_name)

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: DnsServer.Requests},
      {Tcp, [port: 5553]},
      {Udp, [port: 5553]},
      %{id: DnsServer.Db.Cache, start: {DnsServer.Db, :start_link, [[name: @cache_table]]}},
      %{id: DnsServer.Db.Master, start: {DnsServer.Db, :start_link, [[name: @master_table]]}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DnsServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
