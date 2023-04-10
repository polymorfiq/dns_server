defmodule DnsServer.Request do
  use GenServer, restart: :transient
  alias DnsServer.Processor
  alias DnsServer.Message
  require Logger

  @moduledoc """
  An agent that manages a single DNS request through its lifetime.
  Receives queries from and sends responses to the relevant UDP and TCP ports. Converts them to/from raw bits to the `DnsServer.Message` struct.
  The incoming `DnsServer.Message` is then passed to a `DnsServer.Processor` for interpreting and executing the query.

  DnsServer.Request is capable of evolving to handle multiple DNS Queries from the same client, treating it as a single conversation so-as to limit the bandwidth dedicated to a single DNS Client.
  """

  @max_udp_length Application.compile_env(:dns_server, :udp_truncate_length)
  @type conn :: {:udp, {port(), tuple(), integer()}} | {:tcp, port()}
  @type state :: %{conn: conn(), started_at: Time.t()}

  @spec start_link(conn(), keyword()) :: GenServer.on_start()
  def start_link(conn, opts \\ []) do
    GenServer.start_link(__MODULE__, conn, opts)
  end

  @doc """
  Initialize a `DnsServer.Request` server that will manage incoming `DnsServer.Message` and outgoing TCP/UDP data for the lifetime of the client's request
  """
  @impl true
  @spec init(conn()) :: {:ok, state()}
  def init(conn) do
    Logger.info("Client connected: #{inspect(conn)}")
    {:ok, %{conn: conn, started_at: Time.utc_now()}}
  end

  @doc """
  Takes a query (`DnsServer.Message`) in bitstring format from a client. Asynchronously processes and responds to that query
  """
  @spec intake_query(pid(), bitstring()) :: :ok
  def intake_query(request, query_data) do
    GenServer.cast(request, {:intake_query, query_data})
  end

  @doc """
  Asynchronously (FIFO) sends binary data to the client (TCP or UDP) that initiated the query.
  """
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
    data = maybe_truncate_message_data(data)
    :ok = :gen_udp.send(socket, host, port, data)
    {:stop, :normal, state}
  end

  def handle_cast({:send_response, data}, %{conn: {:tcp, socket}} = state) when is_port(socket) do
    :gen_tcp.send(socket, data)

    {:stop, :normal, state}
  end

  # The entrypoint incoming (asynchronous) responses from the `DnsServer.Processor` that's handling the query.
  # Converts the message to a bitstring and forwards it to the connected protocol.
  @impl true
  def handle_info({:processor_response, response}, %{conn: {proto, _}} = state) do
    message = Message.fix_metadata(response)
    Logger.info("ID #{message.header.id} - Sending response (#{proto} - #{message.header.rcode})")

    {:ok, data} = Message.to_bitstring(message)

    send_response(self(), data)
    {:noreply, state}
  end

  # Detect when TCP data comes in, pass it to the centralized intake process
  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    intake_query(self(), data)
    {:noreply, state}
  end

  # Detect when the TCP connection closes. Stop the Request
  @impl true
  def handle_info({:tcp_closed, _}, state) do
    Logger.info("TCP connection closed")
    {:stop, :normal, state}
  end

  # Detect when a TCP error occurs. Stop the Request
  @impl true
  def handle_info({:tcp_error, _, _}, state) do
    Logger.warn("TCP Error ocurred")
    {:stop, :normal, state}
  end

  # Checks if the outgoing UDP packet data is too large.
  # If so, send an empty message with the `tc` boolean set, so that the client will switch to TCP.
  @spec maybe_truncate_message_data(bitstring()) :: bitstring()
  defp maybe_truncate_message_data(message_bs) do
    if String.length(message_bs) > @max_udp_length do
      {:ok, message} = Message.from_bitstring(message_bs)
      message = %{message | question: [], answer: [], authority: [], additional: []}
      message = %{message | header: %{message.header | tc: true}}

      {:ok, data} =
        %{message | header: %{message.header | tc: true}}
        |> Message.fix_metadata()
        |> Message.to_bitstring()

      data
    else
      message_bs
    end
  end
end
