defmodule DnsServer.Client.Udp do
  use GenServer
  require Logger

  @moduledoc """
  Handles outgoing UDP communication with foreign nameservers
  """

  @type state :: %{socket: port(), parent: pid(), host: tuple(), port: integer()}

  @spec start_link(pid(), tuple(), integer()) :: GenServer.on_start()
  def start_link(parent, host, port) do
    GenServer.start_link(__MODULE__, {parent, host, port})
  end

  @impl true
  @spec init({pid(), tuple(), integer()}) :: {:ok, state()}
  def init({parent, host, port}) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])

    {:ok,
     %{
       socket: socket,
       parent: parent,
       host: host,
       port: port
     }}
  end

  @spec send_request(pid(), bitstring()) :: :ok
  def send_request(udp, data) do
    GenServer.cast(udp, {:send_request, data})
  end

  @impl true
  @spec handle_cast({:send_request, bitstring()}, state()) :: {:noreply, state()}
  def handle_cast({:send_request, data}, state) do
    :ok = :gen_udp.send(state.socket, state.host, state.port, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, socket, host, port, data}, state) do
    send(state.parent, {:client_response, :udp, {host, port}, data})
    :gen_udp.close(socket)

    {:stop, :normal, state}
  end
end
