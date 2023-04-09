defmodule DnsServer.Listener.Tcp do
  use GenServer
  alias DnsServer.Request
  require Logger

  def start_link(port: port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, active: true, packet: 2, reuseaddr: true])
    send(self(), :accept)

    {:ok, socket}
  end

  @impl true
  def handle_info(:accept, socket) do
    {:ok, conn_socket} = :gen_tcp.accept(socket)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        DnsServer.Requests,
        {Request, {:tcp, conn_socket}}
      )

    :gen_tcp.controlling_process(conn_socket, pid)

    send(self(), :accept)
    {:noreply, socket}
  end
end
