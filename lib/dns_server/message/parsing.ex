defmodule DnsServer.Message.Parsing do
  @max_label_length Application.compile_env(:dns_server, :message_max_label_length)
  @max_name_length Application.compile_env(:dns_server, :message_max_name_length)

  @type internet_address :: String.t() | integer()
  @type label :: binary()
  @type name :: list(label())
  @type char_string :: String.t()

  @spec internet_address_to_bitstring(internet_address()) ::
          {:ok, bitstring()} | {:error, any()}
  def internet_address_to_bitstring(ip) when is_integer(ip), do: {:ok, <<ip::size(32)>>}

  def internet_address_to_bitstring(ip) when is_binary(ip) do
    with {:ok, {a, b, c, d}} <- :inet.parse_ipv4_address(to_charlist(ip)) do
      {:ok, <<a::size(8), b::size(8), c::size(8), d::size(8)>>}
    else
      {:ok, {_, _, _, _, _, _}} -> {:error, :a_record_unexpected_ipv6}
      _ -> {:error, :unexpected_a_record}
    end
  end

  @spec bitstring_to_internet_address(bitstring()) :: {:ok, internet_address()} | {:error, any()}
  def bitstring_to_internet_address(<<a::8, b::8, c::8, d::8>>), do: {:ok, "#{a}.#{b}.#{c}.#{d}"}

  @spec bitstring_pop_internet_address(bitstring()) ::
          {:ok, internet_address(), bitstring()} | {:error, any()}
  def bitstring_pop_internet_address(<<a::8, b::8, c::8, d::8, rest::binary>>),
    do: {:ok, "#{a}.#{b}.#{c}.#{d}", rest}

  @spec char_strings_to_bitstring([char_string()]) :: {:ok, bitstring()}
  def char_strings_to_bitstring([]), do: {:ok, <<>>}

  def char_strings_to_bitstring([cs | rest]) when is_binary(cs) do
    with {:ok, rest_bs} <- char_strings_to_bitstring(rest) do
      {:ok,
       <<
         String.length(cs)::unsigned-integer-size(8),
         cs::binary,
         rest_bs::binary
       >>}
    end
  end

  @spec bitstring_to_char_strings(bitstring()) :: {:ok, [char_string()]} | {:error, any()}
  def bitstring_to_char_strings(<<>>), do: {:ok, []}

  def bitstring_to_char_strings(<<len::8, rest::binary>>) do
    case rest do
      <<char_str::binary-size(len), remaining::binary>> ->
        with {:ok, char_strs} <- bitstring_to_char_strings(remaining) do
          {:ok, [char_str | char_strs]}
        end

      data ->
        {:error, "Could not read charstring length. Expected #{len} but got #{String.length(data)} from #{inspect(data)}"}
    end
  end

  @spec name_to_bitstring(name()) :: {:ok, bitstring()} | {:error, any()}
  def name_to_bitstring(name) when is_list(name) do
    with {:ok, name_bs} <- name_to_bitstring_helper(name) do
      {:ok, <<name_bs::binary, 0::8>>}
    end
  end

  @spec name_to_bitstring_helper(name()) :: {:ok, bitstring()} | {:error, any()}
  defp name_to_bitstring_helper([]), do: {:ok, <<>>}

  defp name_to_bitstring_helper([label | rest] = name) when is_binary(label) do
    with {:ok, _} <- validate_name(name),
         {:ok, rest_bs} <- name_to_bitstring_helper(rest) do
      {:ok,
       <<
         String.length(label)::signed-integer-size(8),
         label::binary,
         rest_bs::binary
       >>}
    end
  end

  @spec bitstring_to_name(bitstring(), bitstring()) :: {:ok, name()} | {:error, any()}
  def bitstring_to_name(bs, message_bs) do
    with {:ok, name, <<>>} <- bitstring_pop_name(bs, message_bs) do
      {:ok, name}
    else
      {:ok, _, rest} -> {:error, "Data remaining after parsing name: #{inspect(rest)}"}
      err -> err
    end
  end

  @spec bitstring_pop_name(bitstring(), bitstring()) ::
          {:ok, name(), bitstring()} | {:error, any()}
  def bitstring_pop_name(<<len::signed-integer-size(8), rest::binary>>, message_bs) do
    cond do
      Bitwise.band(len, 0b11000000) == 0b11000000 ->
        <<_::2, pointer::14, remaining::binary>> = <<len::8, rest::binary>>

        # Compressed name. Follow pointer
        <<_::binary-size(pointer), name_bs::bitstring>> = message_bs

        with {:ok, name, _} <- bitstring_pop_name(name_bs, message_bs) do
          {:ok, name, remaining}
        end

      len == 0 ->
        {:ok, [], rest}

      len > String.length(rest) ->
        {:error, "Invalid label length: #{len} for #{inspect(rest)}"}

      true ->
        with <<label::binary-size(len), remaining::bitstring>> <- rest,
             {:ok, _} <- validate_label(label),
             {:ok, labels, remaining} <- bitstring_pop_name(remaining, message_bs) do
          {:ok, [label | labels], remaining}
        end
    end
  end

  @spec validate_name(name()) :: {:ok, integer()} | {:error, any()}
  defp validate_name([label | _] = name) when is_binary(label) do
    name
    |> Enum.reduce({:ok, 0}, fn label, acc ->
      with {:ok, octet_count} <- acc,
           {:ok, _} <- validate_label(label) do
        new_octet_count = 1 + String.length(label) + octet_count

        if new_octet_count <= @max_name_length do
          {:ok, new_octet_count}
        else
          {:error, :name_too_long}
        end
      end
    end)
  end

  @spec validate_label(label()) :: {:ok, label()} | {:error, any()}
  defp validate_label(label) when is_binary(label) do
    cond do
      String.length(label) > @max_label_length ->
        {:error, :label_too_long}

      !String.match?(label, ~r/^[a-zA-Z0-9\-]*$/) ->
        {:error, :label_invalid_characters}

      true ->
        {:ok, label}
    end
  end
end
