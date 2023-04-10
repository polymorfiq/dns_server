defmodule DnsServer.Delegate do
  use GenServer
  alias DnsServer.Client.{Tcp, Udp}
  alias DnsServer.Message
  require Logger

  @moduledoc """
  Handles the delegation of a DNS Query (`DnsServer.Message`) to multiple foreign nameservers

  Also handle collecting, aggregating and interpreting the responses of those nameservers, adjusting the connections (UDP/TCP) as needed.
  """

  @foreign_ns Application.compile_env(:dns_server, :foreign_name_servers)
  @type state :: %{parent: pid(), request: Message.t()}

  @spec start_link(pid(), Message.t()) :: GenServer.on_start()
  def start_link(parent, request) do
    GenServer.start_link(__MODULE__, {parent, request})
  end

  @doc """
  Initializes a `DnsServer.Delegate` process, given a parent to report back to and a `DnsServer.Message` to fulfill
  """
  @impl true
  @spec init({pid(), Message.t()}) :: {:ok, state(), {:continue, :ok}}
  def init({parent, request}) do
    {:ok, %{parent: parent, request: request}, {:continue, :ok}}
  end

  @doc """
  Attempt a fan-out set of UDP requests for each foreign nameserver defined in the `config.exs`
  """
  @impl true
  @spec handle_continue(:ok, state()) :: {:noreply, state()}
  def handle_continue(:ok, %{request: request} = state) do
    {:ok, request_data} = Message.to_bitstring(request)

    @foreign_ns
    |> Enum.each(fn {host, port} ->
      {:ok, dns_server} = Udp.start_link(self(), host, port)
      Udp.send_request(dns_server, request_data)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:client_response, proto, {host, port}, data}, state) do
    from_allowed? =
      Enum.find(@foreign_ns, false, fn
        {^host, ^port} -> true
        _ -> false
      end)

    message = from_allowed? && try do
      {:ok, message} = Message.from_bitstring(data)
      message
    rescue
      err in RuntimeError ->
        Logger.error("Error parsing response from #{inspect(host)}:#{port} (#{inspect(state.request.question)}) - #{inspect(err)}")
        nil
    end

    if message do
      Logger.info(
        "ID #{state.request.header.id} - Received Response (#{proto} - #{message.header.rcode}) from #{inspect(host)}:#{port}"
      )

      cond do
        message.header.tc && proto == :udp ->
          # Response was truncated...
          Logger.info(
            "ID #{state.request.header.id} - Truncation header from #{inspect(host)}:#{port}. Switching to TCP..."
          )

          {:ok, request_data} = Message.to_bitstring(state.request)

          {:ok, tcp} = Tcp.start_link(self(), host, port)
          Tcp.send_request(tcp, request_data)

        true ->
          send(state.parent, {:delegate_response, message})
      end
    end

    {:noreply, state}
  end
end
