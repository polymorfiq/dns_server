defmodule DnsServer.Listener.Udp do
  use GenServer
  alias DnsServer.Request
  require Logger

  @moduledoc """
  Handles incoming UDP communication with DNS Clients
  """

  def start_link(port: port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) do
    :gen_udp.open(port, [:binary, active: true])
  end

  @impl true
  def handle_info({:udp, socket, host, port, data}, socket) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        DnsServer.Requests,
        {Request, {:udp, {socket, host, port}}}
      )

    DnsServer.Request.intake_query(pid, data)

    {:noreply, socket}
  end
end
