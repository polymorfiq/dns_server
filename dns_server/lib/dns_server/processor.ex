defmodule DnsServer.Processor do
  use GenServer
  alias DnsServer.Db
  alias DnsServer.Delegate
  alias DnsServer.Message
  require Logger

  @moduledoc """
  A `DnsServer.Processor` interprets and fulfills a single `DnsServer.Message` that represents a single DNS Query.

  Consults the cache (`DnsServer.Db`) and delegates to foreign nameservers (`DnsServer.Delegate`) to build a response `DnsServer.Message` and send that to the `DnsServer.Request` to be distributed to clients.
  """

  @cache_table Application.compile_env(:dns_server, :cache_table_name)
  @type state :: %{parent: pid(), response: Message.t(), request: Message.t(), started_at: Time.t()}
  @type preprocess_error :: :not_implemented

  @spec start_link(pid(), Message.t(), Time.t()) :: GenServer.on_start()
  def start_link(parent, request, started_at) do
    GenServer.start_link(__MODULE__, {parent, request, started_at})
  end

  @doc """
  Initializes a `DnsServer.Processor` server, given a parent process (to callback when finished), a `DnsServer.Message` to respond to, and a `Time` that the query started (for calculating TTLs).
  """
  @impl true
  @spec init({pid(), Message.t(), Time.t()}) :: {:ok, state(), {:continue, Message.t()}}
  def init({parent, request, started_at}) do
    response_header = %Message.Header{
      id: request.header.id,
      qr: :response,
      opcode: request.header.opcode,
      aa: false,
      rd: request.header.rd,
      ra: true
    }

    response = %Message{header: response_header}

    {:ok,
     %{
       parent: parent,
       response: response,
       request: request,
       started_at: started_at
     }, {:continue, request}}
  end

  @doc """
  After initialization, this checks the Master File, the cache (`DnsServer.Db`), and (if necessary) sends unanswered questions to foreign nameservers (`DnsServer.Delegate`)
  """
  @impl true
  @spec handle_continue(Message.t(), state()) :: {:noreply, state()}
  def handle_continue(request, %{request: request} = state) do
    state =
      with {:ok, request} <- preprocess(request) do
        state
        |> maybe_check_master_file(request)
        |> maybe_check_cache(request)
        |> maybe_check_foreign_nameservers(request)
      else
        {:error, :not_implemented} ->
          put_in(
            state,
            [Access.key(:response), Access.key(:header), Access.key(:rcode)],
            :not_implemented
          )
      end

    state
    |> maybe_send_and_stop()
  end

  # Checks the Master File for data relevant to the query (`DnsServer.Message`)
  @spec maybe_check_master_file(state(), Message.t()) :: state()
  defp maybe_check_master_file(%{response: %{header: %{rcode: nil}}} = state, _request), do: state
  defp maybe_check_master_file(state, _request), do: state

  # Checks the local cache (`DnsServer.Db`) for data relevant to the query (`DnsServer.Message`)
  @spec maybe_check_cache(state(), Message.t()) :: state()
  defp maybe_check_cache(%{response: %{header: %{rcode: nil}}} = state, request) do
    cached_questions =
      request.question
      |> Enum.map(fn question ->
        {:ok, resources} = Db.lookup(@cache_table, state.started_at, question)
        {question, resources}
      end)
      |> Enum.filter(fn {_, resources} -> Enum.count(resources) > 0 end)

    cached_questions
    |> Enum.each(fn {question, res} ->
      Logger.info(
        "ID #{request.header.id} - Question found in cache: #{inspect(question.qtype)}, #{inspect(question.qname)} - #{Enum.count(res)} records"
      )
    end)

    answer =
      cached_questions
      |> Enum.flat_map(fn {_, res} -> res end)

    response = state.response
    response = %{response | answer: answer}

    response =
      if Enum.count(cached_questions) == Enum.count(request.question) do
        put_in(response, [Access.key(:header), Access.key(:rcode)], :noerror)
      else
        response
      end

    %{state | response: Message.fix_metadata(response)}
  end

  defp maybe_check_cache(state, _), do: state

  # Starts a `DnsServer.Delegate` that will take the unanswered `DnsServer.Message.Question`s in the query (`DnsServer.Message`) and consult foreign nameservers to get answers.
  @spec maybe_check_foreign_nameservers(state(), Message.t()) :: state()
  defp maybe_check_foreign_nameservers(%{response: %{header: %{rcode: nil}}} = state, request) do
    Delegate.start_link(self(), request)
    state
  end

  defp maybe_check_foreign_nameservers(state, _), do: state

  # Called every time the foreign nameservers (from the `DnsServer.Delegate`) respond to the request
  @impl true
  def handle_info({:delegate_response, foreign_resp}, state) do
    foreign_resp
    |> process_foreign_response(state)
    |> maybe_send_and_stop()
  end

  @doc """
  Takes a response (`DnsServer.Message`) from the foreign nameservers and adds relevant data to the response that's currently being built.
  """
  @spec process_foreign_response(Message.t(), state) :: state()
  def process_foreign_response(%Message{} = message, state) do
    %{response: curr_resp} = state
    question = curr_resp.question ++ message.question

    answer =
      (curr_resp.answer ++ message.answer)
      |> Enum.reject(fn res -> res.type == :NOT_IMPLEMENTED || res.class == :NOT_IMPLEMENTED end)
      |> Enum.uniq_by(fn r -> {r.class, r.type, r.name, r.rdata} end)

    authority =
      (curr_resp.authority ++ message.authority)
      |> Enum.reject(fn res -> res.type == :NOT_IMPLEMENTED || res.class == :NOT_IMPLEMENTED end)
      |> Enum.uniq_by(fn r -> {r.class, r.type, r.name, r.rdata} end)

    additional =
      (curr_resp.additional ++ message.additional)
      |> Enum.reject(fn res -> res.type == :NOT_IMPLEMENTED || res.class == :NOT_IMPLEMENTED end)
      |> Enum.uniq_by(fn r -> {r.class, r.type, r.name, r.rdata} end)

    rcode =
      if Enum.count(question) >= Enum.count(state.request.question) do
        :noerror
      else
        curr_resp.header.rcode
      end

    header = %{curr_resp.header | rcode: rcode}

    response =
      %{
        curr_resp
        | header: header,
          question: question,
          answer: answer,
          authority: authority,
          additional: additional
      }
      |> Message.fix_metadata()

    cond do
      message.header.rcode == :noerror ->
        %{state | response: response}

      true ->
        state
    end
  end

  @doc """
  Checks whether or not the response is ready to be sent to the client (all `DnsServer.Question`s answered).
  If so, send the response and stop the `DnsServer.Processor`.
  """
  @spec maybe_send_and_stop(state) :: {:noreply, state()} | {:stop, :normal, state()}
  def maybe_send_and_stop(state) do
    case state.response do
      %{header: %{rcode: nil}} ->
        {:noreply, state}

      _ ->
        response = Message.fix_metadata(state.response)

        response.answer
        |> Enum.each(fn resource -> Db.store(@cache_table, state.started_at, resource) end)

        send(state.parent, {:processor_response, response})
        {:stop, :normal, state}
    end
  end

  @doc """
  Checks for unimplemented features in the query (`DnsServer.Message`) so that we can respond with a `not_implemented` response code.
  """
  @spec preprocess(Message.t()) :: {:ok, Message.t()} | {:error, preprocess_error()}
  def preprocess(%Message{} = message) do
    unimplemented_qs =
      message.question
      |> Enum.filter(fn q -> q.qtype == :NOT_IMPLEMENTED || q.qclass == :NOT_IMPLEMENTED end)

    unimplemented_res =
      (message.answer ++ message.authority ++ message.additional)
      |> Enum.filter(fn r -> r.type == :NOT_IMPLEMENTED || r.class == :NOT_IMPLEMENTED end)

    cond do
      message.header.opcode == :IQUERY -> {:error, :not_implemented}
      message.header.opcode == :STATUS -> {:error, :not_implemented}
      Enum.count(unimplemented_qs) > 0 -> {:error, :not_implemented}
      Enum.count(unimplemented_res) > 0 -> {:error, :not_implemented}
      true -> {:ok, message}
    end
  end
end
