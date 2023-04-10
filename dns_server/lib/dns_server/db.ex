defmodule DnsServer.Db do
  use GenServer
  alias DnsServer.Message.Parsing
  alias DnsServer.Message.Resource
  alias DnsServer.Message.Question
  require Logger

  @moduledoc """
  An in-memory database for caching and querying DNS Resource Records (`DnsServer.Message.Resource`)
  """

  def start_link(opts) do
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

  @doc """
  Lookup the cached Resource Records (`DnsServer.Message.Resource`) that answer the given Question (`DnsServer.Message.Question`).

  Provided a `Time` so that returned records can be predictably filtered and adjusted via their TTL
  """
  @spec lookup(atom(), Time.t(), Question.t()) :: {:ok, list(Resource.t())}
  def lookup(server, start_time, %Question{} = question) do
    query = {[question.qclass, question.qtype, normalize_name(question.qname)], :_}

    results = :ets.match_object(server, {query, :_, :_})
      |> Enum.map(fn {_, eol, resource} ->
        %{resource | ttl: Time.diff(eol, start_time, :second) }
      end)
      |> Enum.reject(fn %{ttl: ttl} -> ttl < 0 end)

    {:ok, results}
  end

  @doc """
  Store a Resource Records as one of the answers in the cache, with their TTLs adjusted relative to the given `Time`
  """
  @spec store(atom(), Time.t(), Resource.t()) :: :ok
  def store(server, started_at, %Resource{} = resource) do
    GenServer.cast(server, {:store_resource, server, started_at, resource})
  end

  @spec normalize_name(Parsing.name()) :: Parsing.name()
  def normalize_name(name) when is_list(name) do
    name
    |> Enum.map(&String.downcase/1)
  end

  @doc """
  Initializes the in-memory database in which Resource Records are stored
  """
  @impl true
  def init(table) do
    db = :ets.new(table, [:set, :named_table, read_concurrency: true])
    {:ok, %{db: db}}
  end

  @impl true
  def handle_cast({:store_resource, server, started_at, resource}, state) do
    key = {[resource.class, resource.type, normalize_name(resource.name)], resource.rdata}

    eol = Time.add(started_at, resource.ttl, :second)
    :ets.insert(server, {key, eol, resource})

    Process.send_after(self(), {:purge_resource, server, resource, key}, resource.ttl * 1000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:purge_resource, server, resource, key}, state) do
    Logger.info("Purging old record (#{inspect(resource.class)}, #{inspect(resource.type)}, #{inspect(resource.name)})")

    true = :ets.delete(server, key)
    {:noreply, state}
  end
end
