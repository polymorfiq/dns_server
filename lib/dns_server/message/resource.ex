defmodule DnsServer.Message.Resource do
  alias DnsServer.Message.Parsing
  require Logger

  defstruct [
    :name,
    :type,
    :class,
    :ttl,
    :rdlength,
    :rdata
  ]

  @type type ::
          :A
          # Host Address
          | :NS
          # Authoritative Name Server
          | :MD
          # Mail Destination
          | :MF
          # Mail Forwarder
          | :CNAME
          # Canonical Name for an Alias
          | :SOA
          # Start of Zone Authority
          | :MB
          # Mailbox Domain Name
          | :MG
          # Mail Group Member
          | :MR
          # Mail Rename Domain Name
          | :NULL
          # Null Resource
          | :WKS
          # Well known service description
          | :PTR
          # Domain Name Pointer
          | :HINFO
          # Host Information
          | :MX
          # Mailbox or Mail List Information
          | :TXT
          | :NOT_IMPLEMENTED
  # Text Strings

  @type class ::
          :IN
          # The Internet
          | :CS
          # CSNet
          | :CH
          # CHAOS
          | :HS
  # Hesoid

  @type rdata ::
          Parsing.name()
          | {String.t(), String.t()}
          | {[String.t()], [String.t()]}
          | bitstring()
          | {String.t(), String.t(), number(), number(), number(), number(), number()}

  @type t :: %__MODULE__{
          name: Parsing.name(),
          type: type(),
          class: class(),
          ttl: integer(),
          rdlength: integer() | nil,
          rdata: rdata()
        }

  @spec to_bitstring(t()) :: {:ok, bitstring()} | {:error, any()}
  def to_bitstring(%__MODULE__{} = resource) do
    with {:ok, name_bs} <- Parsing.name_to_bitstring(resource.name),
         {:ok, rdata_bs} <- rdata_to_bitstring(resource.type, resource.rdata) do
      rdlength = if resource.rdlength == nil, do: String.length(rdata_bs), else: resource.rdlength

      {:ok,
       <<
         name_bs::binary,
         type_to_bitstring(resource.type)::binary,
         class_to_bitstring(resource.class)::binary,
         resource.ttl::integer-signed-32,
         rdlength::integer-unsigned-16,
         rdata_bs::binary
       >>}
    end
  end

  @spec multi_pop_bitstring(integer(), bitstring(), bitstring()) ::
          {:ok, [t()], bitstring()} | {:error, any()}
  def multi_pop_bitstring(0, bs, _), do: {:ok, [], bs}

  def multi_pop_bitstring(n, bs, message_bs) do
    with {:ok, resource, remaining} <- pop_bitstring(bs, message_bs),
         {:ok, resources, remaining} <- multi_pop_bitstring(n - 1, remaining, message_bs) do
      {:ok, [resource | resources], remaining}
    end
  end

  @spec count_rdlength(t()) :: integer()
  def count_rdlength(%__MODULE__{} = resource) do
    {:ok, data} = rdata_to_bitstring(resource.type, resource.rdata)
    String.length(data)
  end

  @spec pop_bitstring(bitstring(), bitstring()) :: {:ok, t(), bitstring()} | {:error, any()}
  defp pop_bitstring(bs, message_bs) do
    with {:ok, name, remaining} <- Parsing.bitstring_pop_name(bs, message_bs) do
      <<
        type_bs::16,
        class_bs::16,
        ttl::32,
        rdlength::16,
        remaining::binary
      >> = remaining

      <<rdata_bs::binary-size(rdlength), remaining::bitstring>> = remaining

      type = bitstring_to_type(<<type_bs::16>>)
      class = bitstring_to_class(<<class_bs::16>>)

      with {:ok, rdata} <- bitstring_to_rdata(type, rdata_bs, message_bs) do
        {:ok,
         %__MODULE__{
           name: name,
           type: type,
           class: class,
           ttl: ttl,
           rdlength: rdlength,
           rdata: rdata
         }, remaining}
      else
        {:error, err} ->
          Logger.warn(
            "Error parsing #{inspect(type)} - #{inspect(class)} - #{inspect(name)} - Length: #{rdlength} - Data: #{inspect(rdata_bs)}"
          )

          raise "Error parsing rdata for #{inspect(type)} - #{err}"
      end
    end
  end

  @spec type_to_bitstring(type()) :: <<_::16>>
  defp type_to_bitstring(:A), do: <<1::16>>
  defp type_to_bitstring(:NS), do: <<2::16>>
  defp type_to_bitstring(:MD), do: <<3::16>>
  defp type_to_bitstring(:MF), do: <<4::16>>
  defp type_to_bitstring(:CNAME), do: <<5::16>>
  defp type_to_bitstring(:SOA), do: <<6::16>>
  defp type_to_bitstring(:MB), do: <<7::16>>
  defp type_to_bitstring(:MG), do: <<8::16>>
  defp type_to_bitstring(:MR), do: <<9::16>>
  defp type_to_bitstring(:NULL), do: <<10::16>>
  defp type_to_bitstring(:WKS), do: <<11::16>>
  defp type_to_bitstring(:PTR), do: <<12::16>>
  defp type_to_bitstring(:HINFO), do: <<13::16>>
  defp type_to_bitstring(:MINFO), do: <<14::16>>
  defp type_to_bitstring(:MX), do: <<15::16>>
  defp type_to_bitstring(:TXT), do: <<16::16>>

  @spec bitstring_to_type(<<_::16>>) :: type()
  defp bitstring_to_type(<<1::16>>), do: :A
  defp bitstring_to_type(<<2::16>>), do: :NS
  defp bitstring_to_type(<<3::16>>), do: :MD
  defp bitstring_to_type(<<4::16>>), do: :MF
  defp bitstring_to_type(<<5::16>>), do: :CNAME
  defp bitstring_to_type(<<6::16>>), do: :SOA
  defp bitstring_to_type(<<7::16>>), do: :MB
  defp bitstring_to_type(<<8::16>>), do: :MG
  defp bitstring_to_type(<<9::16>>), do: :MR
  defp bitstring_to_type(<<10::16>>), do: :NULL
  defp bitstring_to_type(<<11::16>>), do: :WKS
  defp bitstring_to_type(<<12::16>>), do: :PTR
  defp bitstring_to_type(<<13::16>>), do: :HINFO
  defp bitstring_to_type(<<14::16>>), do: :MINFO
  defp bitstring_to_type(<<15::16>>), do: :MX
  defp bitstring_to_type(<<16::16>>), do: :TXT
  defp bitstring_to_type(_), do: :NOT_IMPLEMENTED

  @spec class_to_bitstring(class()) :: <<_::16>>
  defp class_to_bitstring(:IN), do: <<1::16>>
  defp class_to_bitstring(:CS), do: <<2::16>>
  defp class_to_bitstring(:CH), do: <<3::16>>
  defp class_to_bitstring(:HS), do: <<4::16>>

  @spec bitstring_to_class(<<_::16>>) :: class()
  defp bitstring_to_class(<<1::16>>), do: :IN
  defp bitstring_to_class(<<2::16>>), do: :CS
  defp bitstring_to_class(<<3::16>>), do: :CH
  defp bitstring_to_class(<<4::16>>), do: :HS
  defp bitstring_to_class(_), do: :NOT_IMPLEMENTED

  @spec rdata_to_bitstring(type(), rdata()) :: {:ok, bitstring()} | {:error, any()}
  defp rdata_to_bitstring(:A, ip), do: Parsing.internet_address_to_bitstring(ip)

  defp rdata_to_bitstring(:CNAME, domain) when is_list(domain),
    do: Parsing.name_to_bitstring(domain)

  defp rdata_to_bitstring(:HINFO, {cpu, os}) when is_binary(cpu) and is_binary(os),
    do: Parsing.char_strings_to_bitstring([cpu, os])

  defp rdata_to_bitstring(:MB, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)
  defp rdata_to_bitstring(:MD, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)
  defp rdata_to_bitstring(:MF, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)
  defp rdata_to_bitstring(:MG, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)

  defp rdata_to_bitstring(:MINFO, {rmailbx, emailbx})
       when is_list(rmailbx) and is_list(emailbx) do
    with {:ok, rmailbx_bs} <- Parsing.name_to_bitstring(rmailbx),
         {:ok, emailbx_bs} <- Parsing.name_to_bitstring(emailbx) do
      {:ok, <<rmailbx_bs::binary, emailbx_bs::binary>>}
    end
  end

  defp rdata_to_bitstring(:MR, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)

  defp rdata_to_bitstring(:WKS, {addr, proto, bit_map})
       when is_binary(addr) and is_integer(proto) and is_binary(bit_map) do
    with {:ok, addr_bs} <- Parsing.internet_address_to_bitstring(addr) do
      {:ok, <<addr_bs::binary, proto::8, bit_map::binary>>}
    end
  end

  defp rdata_to_bitstring(:MX, {pref, exchange}) when is_integer(pref) and is_list(exchange) do
    with {:ok, exchange_bs} <- Parsing.name_to_bitstring(exchange) do
      {:ok, <<pref::integer-16, exchange_bs::binary>>}
    end
  end

  defp rdata_to_bitstring(:NS, domain) when is_list(domain), do: Parsing.name_to_bitstring(domain)

  defp rdata_to_bitstring(:PTR, domain) when is_list(domain),
    do: Parsing.name_to_bitstring(domain)

  defp rdata_to_bitstring(:SOA, {mname, rname, serial, refresh, retry, expire, minimum})
       when is_list(mname) and
              is_list(rname) and
              is_integer(serial) and
              is_integer(refresh) and
              is_integer(retry) and
              is_integer(expire) and
              is_integer(minimum) do
    with {:ok, mname_bs} <- Parsing.name_to_bitstring(mname),
         {:ok, rname_bs} <- Parsing.name_to_bitstring(rname) do
      {:ok,
       <<
         mname_bs::binary,
         rname_bs::binary,
         serial::unsigned-integer-32,
         refresh::32,
         retry::32,
         expire::32,
         minimum::unsigned-integer-32
       >>}
    end
  end

  defp rdata_to_bitstring(:TXT, char_strs) when is_list(char_strs),
    do: Parsing.char_strings_to_bitstring(char_strs)

  @spec bitstring_to_rdata(type(), <<_::32>>, bitstring()) :: {:ok, rdata()} | {:error, any()}
  defp bitstring_to_rdata(:A, <<_::8, _::8, _::8, _::8>> = ip_bs, _), do: Parsing.bitstring_to_internet_address(ip_bs)

  defp bitstring_to_rdata(:CNAME, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:HINFO, hinfo_bs, _) do
    with {:ok, datas} <- Parsing.bitstring_to_char_strings(hinfo_bs) do
      [cpu, os] = datas
      {:ok, {cpu, os}}
    end
  end

  defp bitstring_to_rdata(:MB, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:MD, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:MF, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:MG, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:MINFO, minfo_bs, message_bs) do
    with {:ok, rmailbx, remaining} <- Parsing.bitstring_pop_name(minfo_bs, message_bs),
         {:ok, emailbx} <- Parsing.bitstring_to_name(remaining, message_bs) do
      {:ok, {rmailbx, emailbx}}
    end
  end

  defp bitstring_to_rdata(:MR, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:WKS, wks_bs, _) do
    with {:ok, addr, remaining} <- Parsing.bitstring_pop_internet_address(wks_bs) do
      <<proto::8, bit_map::binary>> = remaining
      {:ok, {addr, proto, bit_map}}
    end
  end

  defp bitstring_to_rdata(:MX, <<pref::integer-16, exchange_bs::binary>>, message_bs) do
    with {:ok, exchange} <- Parsing.bitstring_to_name(exchange_bs, message_bs) do
      {:ok, {pref, exchange}}
    end
  end

  defp bitstring_to_rdata(:NS, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:PTR, domain_bs, message_bs),
    do: Parsing.bitstring_to_name(domain_bs, message_bs)

  defp bitstring_to_rdata(:SOA, soa_bs, message_bs) do
    with {:ok, mname, remaining} <- Parsing.bitstring_pop_name(soa_bs, message_bs),
         {:ok, rname, remaining} <- Parsing.bitstring_pop_name(remaining, message_bs) do
      <<serial::unsigned-32, refresh::32, retry::32, expire::32, minimum::unsigned-32>> =
        remaining

      {:ok, {mname, rname, serial, refresh, retry, expire, minimum}}
    end
  end

  defp bitstring_to_rdata(:NOT_IMPLEMENTED, bs, _), do: {:ok, bs}

  defp bitstring_to_rdata(:TXT, txt_bs, _), do: Parsing.bitstring_to_char_strings(txt_bs)
end
