defmodule DnsServer.Client.Tcp do
  use GenServer
  require Logger

  @type state :: %{socket: port(), parent: pid(), host: tuple(), port: integer()}

  @spec start_link(pid(), tuple(), integer()) :: GenServer.on_start()
  def start_link(parent, host, port) do
    GenServer.start_link(__MODULE__, {parent, host, port})
  end

  @impl true
  @spec init({pid(), tuple(), integer()}) :: {:ok, state()}
  def init({parent, host, port}) do
    {:ok, socket} = :gen_tcp.connect(host, port, [:binary, active: true, packet: 2])

    {:ok,
     %{
       socket: socket,
       parent: parent,
       host: host,
       port: port
     }}
  end

  @spec send_request(pid(), bitstring()) :: :ok
  def send_request(tcp, data) do
    GenServer.cast(tcp, {:send_request, data})
  end

  @impl true
  @spec handle_cast({:send_request, bitstring()}, state()) :: {:noreply, state()}
  def handle_cast({:send_request, data}, state) do
    :ok = :gen_tcp.send(state.socket, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _, data}, state) do
    send(state.parent, {:client_response, :tcp, {state.host, state.port}, data})
    :gen_tcp.close(state.socket)

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _}, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:tcp_error, _}, state), do: {:stop, :normal, state}
end
