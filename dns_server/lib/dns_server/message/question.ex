defmodule DnsServer.Message.Question do
  @moduledoc """
  Defines an internal representation of a DNS Message Question, given by the DNS RFC
  RFC: https://www.rfc-editor.org/rfc/rfc1035#section-4.1.2
  """

  defstruct [
    :qname,
    :qtype,
    :qclass
  ]

  alias DnsServer.Message.Parsing
  alias DnsServer.Message.Resource

  @type qtype ::
          Resource.type()
          | :AXFR
          # Request for transfer of an entire zone
          | :MAILB
          # Request for mailbox-related records (MB, MG, or MR)
          | :MAILA
          # Request for mailbox agent Resources
          | :*
  # Request for all records

  @type qclass ::
          Resource.class()
          | :*
  # Any class

  @type t :: %__MODULE__{
          qname: Parsing.name(),
          qtype: qtype(),
          qclass: qclass()
        }

  @doc """
  Converts from a human-readable internal format of a DNS Question, to the byte format defined by the DNS RFC
  """
  @spec to_bitstring(t()) :: {:ok, bitstring()} | {:error, atom()}
  def to_bitstring(%__MODULE__{} = question) do
    with {:ok, qname_bs} <-
           Parsing.name_to_bitstring(question.qname) do
      {:ok,
       <<
         qname_bs::binary,
         qtype_to_bitstring(question.qtype)::binary,
         qclass_to_bitstring(question.qclass)::binary
       >>}
    end
  end

  @doc """
  Pops `n` instances of `DnsServer.Message.Question` off the top of a bitstring that follows the byte format defined in the DNS RFC
  """
  @spec multi_pop_bitstring(integer(), bitstring(), bitstring()) ::
          {:ok, [t()], bitstring()} | {:error, any()}
  def multi_pop_bitstring(0, bs, _), do: {:ok, [], bs}

  def multi_pop_bitstring(n, bs, message_bs) do
    with {:ok, question, remaining} <- pop_bitstring(bs, message_bs),
         {:ok, questions, remaining} <- multi_pop_bitstring(n - 1, remaining, message_bs) do
      {:ok, [question | questions], remaining}
    end
  end

  @spec pop_bitstring(bitstring(), bitstring()) :: {:ok, t(), bitstring()} | {:error, any()}
  defp pop_bitstring(bs, message_bs) do
    with {:ok, qname, remaining} <- Parsing.bitstring_pop_name(bs, message_bs) do
      <<qtype_bs::16, qclass_bs::16, remaining::binary>> = remaining

      {:ok,
       %__MODULE__{
         qname: qname,
         qtype: bitstring_to_qtype(<<qtype_bs::16>>),
         qclass: bitstring_to_qclass(<<qclass_bs::16>>)
       }, remaining}
    end
  end

  @spec qtype_to_bitstring(qtype()) :: bitstring()
  defp qtype_to_bitstring(:A), do: <<1::16>>
  defp qtype_to_bitstring(:NS), do: <<2::16>>
  defp qtype_to_bitstring(:MD), do: <<3::16>>
  defp qtype_to_bitstring(:MF), do: <<4::16>>
  defp qtype_to_bitstring(:CNAME), do: <<5::16>>
  defp qtype_to_bitstring(:SOA), do: <<6::16>>
  defp qtype_to_bitstring(:MB), do: <<7::16>>
  defp qtype_to_bitstring(:MG), do: <<8::16>>
  defp qtype_to_bitstring(:MR), do: <<9::16>>
  defp qtype_to_bitstring(:NULL), do: <<10::16>>
  defp qtype_to_bitstring(:WKS), do: <<11::16>>
  defp qtype_to_bitstring(:PTR), do: <<12::16>>
  defp qtype_to_bitstring(:HINFO), do: <<13::16>>
  defp qtype_to_bitstring(:MINFO), do: <<14::16>>
  defp qtype_to_bitstring(:MX), do: <<15::16>>
  defp qtype_to_bitstring(:TXT), do: <<16::16>>
  defp qtype_to_bitstring(:AFXR), do: <<252::16>>
  defp qtype_to_bitstring(:MAILB), do: <<253::16>>
  defp qtype_to_bitstring(:MAILA), do: <<254::16>>
  defp qtype_to_bitstring(:*), do: <<255::16>>

  @spec bitstring_to_qtype(<<_::16>>) :: qtype()
  defp bitstring_to_qtype(<<1::16>>), do: :A
  defp bitstring_to_qtype(<<2::16>>), do: :NS
  defp bitstring_to_qtype(<<3::16>>), do: :MD
  defp bitstring_to_qtype(<<4::16>>), do: :MF
  defp bitstring_to_qtype(<<5::16>>), do: :CNAME
  defp bitstring_to_qtype(<<6::16>>), do: :SOA
  defp bitstring_to_qtype(<<7::16>>), do: :MB
  defp bitstring_to_qtype(<<8::16>>), do: :MG
  defp bitstring_to_qtype(<<9::16>>), do: :MR
  defp bitstring_to_qtype(<<10::16>>), do: :NULL
  defp bitstring_to_qtype(<<11::16>>), do: :WKS
  defp bitstring_to_qtype(<<12::16>>), do: :PTR
  defp bitstring_to_qtype(<<13::16>>), do: :HINFO
  defp bitstring_to_qtype(<<14::16>>), do: :MINFO
  defp bitstring_to_qtype(<<15::16>>), do: :MX
  defp bitstring_to_qtype(<<16::16>>), do: :TXT
  defp bitstring_to_qtype(<<252::16>>), do: :AFXR
  defp bitstring_to_qtype(<<253::16>>), do: :MAILB
  defp bitstring_to_qtype(<<254::16>>), do: :MAILA
  defp bitstring_to_qtype(<<255::16>>), do: :*
  defp bitstring_to_qtype(_), do: :NOT_IMPLEMENTED

  @spec qclass_to_bitstring(qclass()) :: <<_::16>>
  defp qclass_to_bitstring(:IN), do: <<1::16>>
  defp qclass_to_bitstring(:CS), do: <<2::16>>
  defp qclass_to_bitstring(:CH), do: <<3::16>>
  defp qclass_to_bitstring(:HS), do: <<4::16>>
  defp qclass_to_bitstring(:*), do: <<255::16>>

  @spec bitstring_to_qclass(<<_::16>>) :: qclass()
  defp bitstring_to_qclass(<<1::16>>), do: :IN
  defp bitstring_to_qclass(<<2::16>>), do: :CS
  defp bitstring_to_qclass(<<3::16>>), do: :CH
  defp bitstring_to_qclass(<<4::16>>), do: :HS
  defp bitstring_to_qclass(<<255::16>>), do: :*
  defp bitstring_to_qclass(_), do: :NOT_IMPLEMENTED
end
