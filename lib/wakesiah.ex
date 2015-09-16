defmodule Wakesiah do
  use GenServer

  require Logger

  # Client

  def start(opts \\ []) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def stop(pid) do
    GenServer.cast(pid, :terminate)
  end

  def members(), do: members(:wakesiah)
  def members(pid) do
    GenServer.call(pid, :members)
  end

  def connect(connect_to), do: connect(:wakesiah, connect_to)
  def connect(pid, connect_to) do
    try do
      GenServer.call(pid, {:connect, connect_to}, 1000)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def join(pid, connect_to) when is_pid(connect_to) do
    GenServer.call(pid, {:join, connect_to})
  end

  # Server (callbacks)

  def init(:ok) do
    state = %{members: HashDict.new, tasks: HashSet.new}
    :erlang.send_after(1000, self, :tick)
    {:ok, state}
  end

  def handle_call(:members, _from, state) do
    members = HashDict.keys(state.members)
    {:reply, members, state}
  end

  def handle_call({:ping, peer}, _from, state) do
    members = HashDict.put(state.members, peer, :ok)
    {:reply, {:pong, self}, %{state | members: members}}
  end

  def handle_call({:connect, node_name}, from, state) when is_atom(node_name) do
    connect_task = Wakesiah.Task.Connect.start_task(node_name, self(), from)
    Logger.info("Connecting from: #{inspect self()} to: #{inspect node_name}")
    state = %{state | tasks: [connect_task] |> Enum.into(state.tasks)}
    {:noreply, state}
  end

  def handle_call({:connect, pid}, from, state) when is_pid(pid) do
    connect_task = Wakesiah.Task.Connect.start_task(node(), pid, from)
    Logger.info("Connecting from: #{inspect self()} to: #{inspect pid}")
    state = %{state | tasks: [connect_task] |> Enum.into(state.tasks)}
    {:noreply, state}
  end

  def handle_call({:join, connect_to}, _from, state) do
    {:pong, pid} = GenServer.call(connect_to, :ping)
    members = HashDict.put(state.members, pid, :ok)
    state = %{state | members: members}
    {:reply, :ok, state}
  end

  def handle_cast(:terminate, state) do
    {:stop, :shutdown, state}
  end

  def handle_info(:tick, state) do
    :erlang.send_after(5000, self, :tick)
    Logger.debug("Firing tick event")
    {:noreply, state}
  end

  def handle_info(msg = {ref, _}, state) when is_reference(ref) do
    case Task.find(state.tasks, msg) do
      {{:ok, pid, from}, task} ->
        members = HashDict.put(state.members, node(pid), :ok)
        tasks = Set.delete(state.tasks, task)
        response = {:ok, :connected}
        GenServer.reply(from, response)
        {:noreply, %{state | members: members, tasks: tasks}}
      {{:error, {reason, _ }}, %Task{}} ->
        Logger.info("Peer down: #{inspect reason}")
        {:noreply, state}
    end
  end

end
