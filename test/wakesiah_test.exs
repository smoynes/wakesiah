defmodule WakesiahTest do
  require Logger
  use ExUnit.Case, async: true

  setup context do
    fd = String.to_atom("#{context.test} failure detector")
    {:ok, pid} = Wakesiah.Supervisor.start_link(
      worker_name: context.test,
      failure_detector: fd)

    on_exit fn ->
      Wakesiah.stop pid
    end

    {:ok, [pid: context.test, failure_detector: fd]}
  end

  test "members on start", context do
    assert [] = Wakesiah.members(context.pid)
  end

  test "members with seeding", context do
    {:ok, _} = Wakesiah.Supervisor.start_link(
      seeds: [:peer_addr],
      worker_name: String.to_atom("#{context.line}"),
      failure_detector: String.to_atom("#{context.line} failure detector"))
    assert [:peer_addr] = Wakesiah.members(String.to_atom("#{context.line}"))
  end

  test "ping" do
    test_pid = self
    task = Task.async(fn -> Wakesiah.ping(test_pid, 0) end)
    assert_receive {:"$gen_call", msg, {:ping, 0}}
    GenServer.reply(msg, :ack)
    assert :ack = Task.await(task)
  end

  test "ping timeout" do
    assert {:timeout, _} = catch_exit(Wakesiah.ping(self, 0))
    assert_receive {:"$gen_call", _, {:ping, 0}}
  end

  test "task", context do
    task = Wakesiah.Tasks.ping(context.failure_detector, self, 0)
    :pang = Task.await(task)
    assert_receive {:"$gen_call", _, {:ping, 0}}
  end

  test "join", context do
    {:ok, peer} = Wakesiah.start_link(name: :"another #{context.test}")
    assert :ok = Wakesiah.join(context.pid, :"another #{context.test}", {peer, node()})
    assert Wakesiah.members(peer) == [{:"another #{context.test}", node()}]
    assert Wakesiah.members(context.pid) == [{:"another #{context.test}", node()}]
    assert_receive {:broadcast, _}
  end

end
