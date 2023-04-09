defmodule DnsServer.Request do
  use GenServer, restart: :transient
  alias DnsServer.Processor
  alias DnsServer.Message
  require Logger

  @max_udp_length Application.compile_env(:dns_server, :udp_truncate_length)
  @type conn :: {:udp, {port(), tuple(), integer()}} | {:tcp, port()}
  @type state :: %{conn: conn(), started_at: Time.t()}

  @spec start_link(conn(), keyword()) :: GenServer.on_start()
  def start_link(conn, opts \\ []) do
    GenServer.start_link(__MODULE__, conn, opts)
  end

  @impl true
  @spec init(conn()) :: {:ok, state()}
  def init(conn) do
    Logger.info("Client connected: #{inspect(conn)}")
    {:ok, %{conn: conn, started_at: Time.utc_now()}}
  end

  @spec intake_query(pid(), bitstring()) :: :ok
  def intake_query(request, query_data) do
    GenServer.cast(request, {:intake_query, query_data})
  end

  @spec send_response(pid(), bitstring()) :: :ok
  def send_response(request, response_data) do
    GenServer.cast(request, {:send_response, response_data})
  end

  @impl true
  @spec handle_cast({:intake_query, bitstring()}, state()) :: {:noreply, state()}
  def handle_cast({:intake_query, data}, state) do
    {:ok, request} = Message.from_bitstring(data)

    Processor.start_link(self(), request, state.started_at)
    {:noreply, state}
  end

  @impl true
  @spec handle_cast({:send_response, bitstring()}, state()) :: {:noreply, state()}
  def handle_cast({:send_response, data}, %{conn: {:udp, {socket, host, port}}} = state) do
    data =
      if String.length(data) <= @max_udp_length do
        data
      else
        # UDP response is too large. Truncate it
        {:ok, message} = Message.from_bitstring(data)
        message = %{message | question: [], answer: [], authority: [], additional: []}
        message = %{message | header: %{message.header | tc: true}}

        {:ok, data} =
          %{message | header: %{message.header | tc: true}}
          |> Message.fix_metadata()
          |> Message.to_bitstring()

        data
      end

    :ok = :gen_udp.send(socket, host, port, data)
    {:stop, :normal, state}
  end

  def handle_cast({:send_response, data}, %{conn: {:tcp, socket}} = state) when is_port(socket) do
    :gen_tcp.send(socket, data)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:processor_response, response}, %{conn: {proto, _}} = state) do
    message = Message.fix_metadata(response)
    Logger.info("ID #{message.header.id} - Sending response (#{proto} - #{message.header.rcode})")

    {:ok, data} = Message.to_bitstring(message)

    send_response(self(), data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    intake_query(self(), data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _}, state) do
    Logger.info("TCP connection closed")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _, _}, state) do
    Logger.warn("TCP Error ocurred")
    {:stop, :normal, state}
  end
end
