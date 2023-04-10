defmodule DnsServer.Message.Header do
  @moduledoc """
  Defines an internal representation of a DNS Message Header, given by the DNS RFC
  RFC: https://www.rfc-editor.org/rfc/rfc1035#section-4.1.1
  """

  defstruct [
    # Identifier, shared by query and response
    :id,
    # 0 if query, 1 if response
    :qr,
    # Externally meaningful - copied from query to response
    opcode: :QUERY,
    # Specifies that the responding server is authoritative
    aa: false,
    # Specifies whether the message is truncated
    tc: false,
    # Whether or not recursion is desired
    rd: false,
    # Specifies if recursion was available
    ra: false,
    # Response code
    rcode: nil,
    # Reserved
    z: 0,
    # Number of questions in the request
    qdcount: nil,
    # Number of answers in the response
    ancount: nil,
    # Number of Name Service records in authority records section
    nscount: nil,
    # Number of resource records in additional records section
    arcount: nil
  ]

  @type qr :: :query | :response
  @type opcode :: :QUERY | :IQUERY | :STATUS
  @type rcode ::
          nil
          | :noerror
          | :format_error
          | :server_failure
          | :name_error
          | :not_implemented
          | :refused
  @type t :: %__MODULE__{
          id: number(),
          qr: qr(),
          opcode: opcode(),
          aa: boolean(),
          tc: boolean(),
          rd: boolean(),
          ra: boolean(),
          z: any(),
          rcode: rcode(),
          qdcount: integer() | nil,
          ancount: integer() | nil,
          nscount: integer() | nil,
          arcount: integer() | nil
        }

  @spec to_bitstring(t()) :: {:ok, <<_::96>>} | {:error, any()}
  def to_bitstring(%__MODULE__{} = header) do
    qr =
      case header.qr do
        :response -> 1
        :query -> 0
      end

    aa = if header.aa, do: 1, else: 0
    tc = if header.tc, do: 1, else: 0
    rd = if header.rd, do: 1, else: 0
    ra = if header.ra, do: 1, else: 0

    {:ok,
     <<
       header.id::size(16),
       qr::size(1),
       opcode_to_bitstring(header.opcode)::bitstring,
       aa::size(1),
       tc::size(1),
       rd::size(1),
       ra::size(1),
       header.z::size(3),
       rcode_to_bitstring(header.rcode)::bitstring,
       header.qdcount::size(16),
       header.ancount::size(16),
       header.nscount::size(16),
       header.arcount::size(16)
     >>}
  end

  @doc """
  Pops a `DnsServer.Message.Header` off the top of a bitstring
  """
  @spec pop_bitstring(bitstring()) :: {:ok, t(), bitstring()} | {:error, any()}
  def pop_bitstring(<<header_bs::binary-size(12), remaining::binary>>) do
    with {:ok, header} <- from_bitstring(header_bs) do
      {:ok, header, remaining}
    end
  end

  @doc """
  Turns a bitstring of the correct length to a `DnsServer.Message.Header`
  """
  @spec from_bitstring(<<_::96>>) :: {:ok, t()} | {:error, any()}
  def from_bitstring(<<
        id::size(16),
        qr::size(1),
        opcode::size(4),
        aa::size(1),
        tc::size(1),
        rd::size(1),
        ra::size(1),
        z::size(3),
        rcode::size(4),
        qdcount::size(16),
        ancount::size(16),
        nscount::size(16),
        arcount::size(16)
      >>) do
    {:ok,
     %__MODULE__{
       id: id,
       qr: if(qr == 1, do: :response, else: :query),
       opcode: bitstring_to_opcode(<<opcode::4>>),
       aa: if(aa == 1, do: true, else: false),
       tc: if(tc == 1, do: true, else: false),
       rd: if(rd == 1, do: true, else: false),
       ra: if(ra == 1, do: true, else: false),
       z: z,
       rcode: bitstring_to_rcode(<<rcode::4>>),
       qdcount: qdcount,
       ancount: ancount,
       nscount: nscount,
       arcount: arcount
     }}
  end

  @spec opcode_to_bitstring(opcode()) :: <<_::4>>
  defp opcode_to_bitstring(:QUERY), do: <<0::size(4)>>
  defp opcode_to_bitstring(:IQUERY), do: <<1::size(4)>>
  defp opcode_to_bitstring(:STATUS), do: <<2::size(4)>>

  @spec bitstring_to_opcode(<<_::4>>) :: opcode()
  defp bitstring_to_opcode(<<0::size(4)>>), do: :QUERY
  defp bitstring_to_opcode(<<1::size(4)>>), do: :IQUERY
  defp bitstring_to_opcode(<<2::size(4)>>), do: :STATUS

  @spec rcode_to_bitstring(rcode() | nil) :: <<_::4>>
  defp rcode_to_bitstring(:noerror), do: <<0::size(4)>>
  defp rcode_to_bitstring(:format_error), do: <<1::size(4)>>
  defp rcode_to_bitstring(:server_failure), do: <<2::size(4)>>
  defp rcode_to_bitstring(:name_error), do: <<3::size(4)>>
  defp rcode_to_bitstring(:not_implemented), do: <<4::size(4)>>
  defp rcode_to_bitstring(:refused), do: <<5::size(4)>>

  @spec bitstring_to_rcode(<<_::4>>) :: rcode()
  defp bitstring_to_rcode(<<0::size(4)>>), do: :noerror
  defp bitstring_to_rcode(<<1::size(4)>>), do: :format_error
  defp bitstring_to_rcode(<<2::size(4)>>), do: :server_failure
  defp bitstring_to_rcode(<<3::size(4)>>), do: :name_error
  defp bitstring_to_rcode(<<4::size(4)>>), do: :not_implemented
  defp bitstring_to_rcode(<<5::size(4)>>), do: :refused
  defp bitstring_to_rcode(<<_::size(4)>>), do: :server_failure
end
