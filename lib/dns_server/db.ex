defmodule DnsServer.Db do
  use GenServer
  alias DnsServer.Message.Parsing
  alias DnsServer.Message.Resource
  alias DnsServer.Message.Question
  require Logger

  def start_link(opts) do
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

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

  @spec store(atom(), Time.t(), Resource.t()) :: :ok
  def store(server, started_at, %Resource{} = resource) do
    GenServer.cast(server, {:store_resource, server, started_at, resource})
  end

  @spec normalize_name(Parsing.name()) :: Parsing.name()
  def normalize_name(name) when is_list(name) do
    name
    |> Enum.map(&String.downcase/1)
  end

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
