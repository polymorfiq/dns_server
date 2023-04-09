# DNS Server

This is an implementation of the DNS System/Protocol

This library serves mainly as an educational project. It may serve future usage as part of larger tools and may continue to implement more RFCs related to DNS.

This application is intended primarily as a resolver without any Zones of its own. Master Files have currently been left out of the implementation due to the fact that authoritative zones should likely use much more tried-and-true solutions for their DNS server of choice.

## RFC Implementations
[rfc1035](https://www.rfc-editor.org/rfc/rfc1035)
[Mostly Completed] - Master File IQuery, Status, not implemented

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dns_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dns_server, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/dns_server>.

