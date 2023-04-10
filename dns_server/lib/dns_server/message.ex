defmodule DnsServer.Message do
  alias DnsServer.Message.{
    Header,
    Question,
    Resource
  }

  @moduledoc """
  Represents a `DNS Message` as defined in the DNS Protocol. Can represent either a DNS Query or a Response to a Query.

  RFC: https://www.rfc-editor.org/rfc/rfc1035#section-4.1.1
  """

  defstruct [
    :header,
    question: [],
    answer: [],
    authority: [],
    additional: []
  ]

  @type t :: %__MODULE__{
          header: Header.t(),
          question: list(Question.t()),
          answer: list(Resource.t()),
          authority: list(Resource.t()),
          additional: list(Resource.t())
        }

  @doc """
  Transforms a `DnsServer.Message` so that its' counts (`qdcount`, `ancount`, ...) and lengths (`rdlength`) match its' contents.
  """
  @spec fix_metadata(t()) :: t()
  def fix_metadata(%__MODULE__{} = message) do
    header =
      message.header
      |> fix_header_metadata(message)

    question =
      message.question
      |> Enum.map(&fix_resource_metadata/1)

    answer =
      message.answer
      |> Enum.map(&fix_resource_metadata/1)

    authority =
      message.authority
      |> Enum.map(&fix_resource_metadata/1)

    additional =
      message.additional
      |> Enum.map(&fix_resource_metadata/1)

    %{
      message
      | header: header,
        question: question,
        answer: answer,
        authority: authority,
        additional: additional
    }
  end

  @spec fix_header_metadata(Header.t(), t()) :: Header.t()
  defp fix_header_metadata(%Header{} = header, %__MODULE__{} = message) do
    %{
      header
      | qdcount: Enum.count(message.question),
        ancount: Enum.count(message.answer),
        nscount: Enum.count(message.authority),
        arcount: Enum.count(message.additional)
    }
  end

  @spec fix_resource_metadata(Resource.t()) :: Resource.t()
  defp fix_resource_metadata(%Resource{} = resource) do
    %{resource | rdlength: Resource.count_rdlength(resource)}
  end

  defp fix_resource_metadata(resource), do: resource

  @doc """
  Converts a `DnsServer.Message` to the DNS Message byte format (as defined by the RFC) to be transferred over a wire
  RFC: https://www.rfc-editor.org/rfc/rfc1035#section-4.1.1
  """
  @spec to_bitstring(t()) :: {:ok, bitstring()} | {:error, any()}
  def to_bitstring(%__MODULE__{} = message) do
    with {:ok, header_bs} <- Header.to_bitstring(message.header),
         {:ok, question_bs} <-
           questions_to_bitstring(message.question),
         {:ok, answer_bs} <- resources_to_bitstring(message.answer),
         {:ok, authority_bs} <- resources_to_bitstring(message.authority),
         {:ok, additional_bs} <- resources_to_bitstring(message.additional) do
      {:ok,
       <<
         header_bs::binary,
         question_bs::binary,
         answer_bs::binary,
         authority_bs::binary,
         additional_bs::binary
       >>}
    end
  end

  @doc """
  Takes the byte data for a DNS Message, as described by the RFC, and converts it to a human-readable internal format (`DnsServer.Message`)
  RFC: https://www.rfc-editor.org/rfc/rfc1035#section-4.1.1
  """
  @spec from_bitstring(bitstring()) :: {:ok, t()} | {:error, any()}
  def from_bitstring(bs) when is_bitstring(bs) do
    {:ok, header, remaining} = Header.pop_bitstring(bs)
    {:ok, question, remaining} = Question.multi_pop_bitstring(header.qdcount, remaining, bs)
    {:ok, answer, remaining} = Resource.multi_pop_bitstring(header.ancount, remaining, bs)
    {:ok, authority, remaining} = Resource.multi_pop_bitstring(header.nscount, remaining, bs)
    {:ok, additional, <<>>} = Resource.multi_pop_bitstring(header.arcount, remaining, bs)

    {:ok,
     %__MODULE__{
       header: header,
       question: question,
       answer: answer,
       authority: authority,
       additional: additional
     }}
  end

  @spec questions_to_bitstring(list(Question.t())) :: {:ok, bitstring()} | {:error, any()}
  defp questions_to_bitstring(questions) do
    questions
    |> Enum.reduce({:ok, <<>>}, fn question, acc ->
      with {:ok, curr} <- acc,
           {:ok, question_bs} <- Question.to_bitstring(question) do
        {:ok, <<curr::binary, question_bs::binary>>}
      end
    end)
  end

  @spec resources_to_bitstring(list(Resource.t())) :: {:ok, bitstring()} | {:error, any()}
  defp resources_to_bitstring(resources) do
    resources
    |> Enum.reduce({:ok, <<>>}, fn resource, acc ->
      with {:ok, curr} <- acc,
           {:ok, resource_bs} <- Resource.to_bitstring(resource) do
        {:ok, <<curr::binary, resource_bs::binary>>}
      end
    end)
  end
end
