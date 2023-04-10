defmodule DnsServer.MessageTest do
  use ExUnit.Case
  alias DnsServer.Message
  alias DnsServer.Message.{Header, Question, Resource}
  doctest Message

  test "serialization/deserialization is consistent (1)" do
    message =
      %Message{
        header: %Header{
          id: 123,
          qr: :query,
          rcode: :noerror,
          opcode: :QUERY
        },
        question: [question("example.com", :A)],
        additional: [
          resource("example.com", :CNAME, ["example2", "com"])
        ]
      }
      |> Message.fix_metadata()

    {:ok, serialized} = Message.to_bitstring(message)
    {:ok, deserialized} = Message.from_bitstring(serialized)
    assert message == deserialized
  end

  test "serialization/deserialization is consistent (2)" do
    message =
      %Message{
        header: %Header{id: 456, qr: :response, rcode: :noerror},
        question: [
          question("mysite.com", :*),
          question("mysite.org", :*)
        ],
        answer: [
          resource("home.mysite.com", :A, "5.5.5.5"),
          resource("mysite.org", :A, "4.4.4.4"),
          resource("mysite.com", :CNAME, ["home", "mysite", "com"]),
          resource("mysite.com", :MX, {10, ["mail", "mysite", "com"]})
        ]
      }
      |> Message.fix_metadata()

    {:ok, serialized} = Message.to_bitstring(message)
    {:ok, deserialized} = Message.from_bitstring(serialized)
    assert message == deserialized
  end

  test "serialization/deserialization is consistent (3)" do
    message =
      %Message{
        header: %Header{
          id: 1,
          qr: :response,
          rcode: :noerror,
          opcode: :QUERY
        },
        question: [
          question("mysite.com", :*)
        ],
        answer: [
          resource("main.mysite.info", :A, "5.5.5.5"),
          resource("mail1.mysite.info", :A, "3.3.3.3"),
          resource("mail2.mysite.info", :A, "3.3.3.4"),
          resource("ns.mysite.info", :A, "3.3.3.128"),
          resource("ns2.mysite.info", :A, "3.3.3.231"),
          resource("mysite.info", :CNAME, ["main", "mysite", "info"]),
          resource("mysite.info", :HINFO, {"INTEL-386", "Windows"}),
          resource("mysite.info", :MB, ["mail", "mysite", "info"]),
          resource("mysite.info", :MD, ["mail", "mysite", "info"]),
          resource("mysite.info", :MF, ["mail", "mysite", "info"]),
          resource("mysite.info", :MG, ["mail", "mysite", "info"]),
          resource(
            "mysite.info",
            :MINFO,
            {["mail", "mysite", "info"], ["mail", "mysite", "info"]}
          ),
          resource("mysite.info", :MR, ["mail", "mysite", "info"]),
          resource(
            "mysite.info",
            :WKS,
            {"1.1.1.1", 6, <<1::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1>>}
          ),
          resource("mysite.info", :MX, {10, ["mail1", "mysite", "info"]}),
          resource("mysite.info", :NS, ["ns", "mysite", "info"]),
          resource("mysite.info", :PTR, ["main", "mysite", "info"]),
          resource(
            "mysite.info",
            :SOA,
            {["ns2", "mysite", "info"], ["mail1", "mysite", "info"], 123, 120, 120, 120, 0}
          ),
          resource("mysite.info", :TXT, ["This_is_some_text", "Other_Text", "\"More Text\""])
        ]
      }
      |> Message.fix_metadata()

    {:ok, serialized} = Message.to_bitstring(message)
    {:ok, deserialized} = Message.from_bitstring(serialized)
    assert message == deserialized
  end

  test "parses compressed domain names" do
    header = %Header{
      id: 1,
      qr: :query,
      opcode: :QUERY,
      aa: false,
      tc: false,
      rd: false,
      ra: false,
      rcode: :noerror,
      z: 0,
      qdcount: 3,
      ancount: 0,
      nscount: 0,
      arcount: 0
    }

    {:ok, header_bs} =
      header
      |> Header.to_bitstring()

    question1_bs = <<4, "test", 5, "myapp", 3, "com", 0, 1::16, 1::16>>

    q_start_offset = String.length(header_bs)
    test_offset = q_start_offset
    question2_bs = <<9, "subdomain", 1::1, 1::1, test_offset::14, 1::16, 1::16>>

    myapp_offset = q_start_offset + 5
    question3_bs = <<5, "other", 1::1, 1::1, myapp_offset::14, 5::16, 1::16>>

    {:ok, message} =
      <<header_bs::binary, question1_bs::binary, question2_bs::binary, question3_bs::binary>>
      |> Message.from_bitstring()

    assert %Message{
             header: header,
             question: [
               question("test.myapp.com", :A),
               question("subdomain.test.myapp.com", :A),
               question("other.myapp.com", :CNAME)
             ]
           } == message
  end

  test "handles empty domains" do
    message =
      %Message{
        header: %Header{
          id: 123,
          qr: :response,
          rcode: :noerror,
          opcode: :QUERY
        },
        question: [question("", :CNAME)],
        answer: [
          resource("", :CNAME, ["example", "com"])
        ]
      }
      |> Message.fix_metadata()

    {:ok, serialized} = Message.to_bitstring(message)
    {:ok, deserialized} = Message.from_bitstring(serialized)
    assert message == deserialized
  end

  @spec question(String.t(), Question.qtype()) :: Question.t()
  defp question(name, qtype) do
    %Question{
      qname: if(name == "", do: [], else: String.split(name, ".")),
      qtype: qtype,
      qclass: :IN
    }
  end

  @spec resource(String.t(), Resource.type(), any()) :: Resource.t()
  defp resource(name, type, rdata) do
    %Resource{
      name: if(name == "", do: [], else: String.split(name, ".")),
      type: type,
      class: :IN,
      ttl: 120,
      rdata: rdata
    }
  end
end
