defmodule Wakesiah.FailureDetector do

  use GenServer
  require Logger
  alias Wakesiah.Membership
  alias Wakesiah.Broadcast

  @name __MODULE__
  @periodic_ping_timeout 1_000

  defmodule State do
    defstruct [:me, :peers, :incarnation, :timer, :tasks, :broadcast]
  end

  def start_link(options \\ [name: @name]) do
    name = Keyword.get(options, :name, @name)
    {seeds, options} = Keyword.pop(options, :seeds, [])
    {id, options} = Keyword.pop(options, :id, name)
    GenServer.start_link(__MODULE__, {id, seeds}, options)
  end

  def members(pid \\ @name) do
    GenServer.call(pid, :members)
  end

  def update(peer_id, new_status), do: update(@name, peer_id, new_status)
  def update(pid, peer_id, new_status) do
    GenServer.call(pid, {:update, peer_id, new_status})
  end

  def peer(peer_id), do: peer(@name, peer_id)
  def peer(pid, peer_id) do
    GenServer.call(pid, {:peer, peer_id})
  end

  def init({id, seeds}) when is_list(seeds) do
    peers = Membership.new(seeds)
    timer = :timer.send_after(@periodic_ping_timeout, :tick)
    {:ok, %State{me: id,
                 peers: peers,
                 incarnation: 0,
                 timer: timer,
                 tasks: [],
                 broadcast: Broadcast.new}}
  end

  def handle_call(:members, _from, state = %State{}) do
    members = Membership.members(state.peers)
    {:reply, members, state}
  end

  def handle_call({:update, peer_id, {event, inc}}, _from, state = %State{}) do
    Logger.debug("Updating: #{inspect peer_id} #{inspect {event, inc}}")
    {gossip, peers} = Membership.update(state.peers, peer_id, {event, inc})
    Logger.debug("Peers: #{inspect peers}")
    case gossip do
      :new ->
        Logger.info("Adding peer: #{inspect peer_id}")
        broadcast = Broadcast.push(state.broadcast, {peer_id, event, inc})
        Logger.debug("Broadcast: #{inspect broadcast}")
        {:reply, :ok, %State{state | peers: peers, broadcast: broadcast}}
      _ ->
        {:reply, :ok, %State{state | peers: peers}}
    end
  end

  def handle_call({:ping, inc, gossip}, _from, state = %State{}) do
    Logger.debug("Received ping: #{inspect inc}, gossip: #{inspect gossip}")
    peers = Enum.reduce(gossip, state.peers, fn (v, acc) -> 
      {peer_addr, event, peer_inc} = v
      {_gossip, acc} = Membership.update(acc, peer_addr, {event, peer_inc})
      acc
    end)
    {:reply, {:ack, state.incarnation}, %State{state | peers: peers}}
  end

  def handle_info(:tick, state = %State{incarnation: inc}) do
    Logger.debug("Handling :tick #{inspect state}")
    if Enum.empty?(state.peers) do
      timer = :timer.send_after(@periodic_ping_timeout, :tick)
      {:noreply, %State{state | timer: timer}}
    else
      peer_addr = Membership.random(state.peers)
      {gossip, broadcast} = Broadcast.pop(state.broadcast)
      task = tasks_mod.ping(self, peer_addr, inc, gossip)
      tasks = [task | state.tasks]
      timer = :timer.send_after(@periodic_ping_timeout, :tick)
      {:noreply, %State{state | timer: timer, tasks: tasks, broadcast: broadcast}}
    end      
  end

  def handle_info(msg = {ref, _}, state = %State{}) when is_reference(ref) do
    case Task.find(state.tasks, msg) do
      {resp, task} ->
        Logger.debug("Task #{inspect task} returned: #{inspect resp}")
        {:noreply, %State{state | tasks: List.delete(state.tasks, task)}}
    end
  end

  def handle_cast({:joined, peer_addr}, state) do
    Logger.debug("Received cast #{inspect state.me} #{inspect {:joined, peer_addr}}")
    {_, peers} = Membership.update(state.peers, peer_addr, {:alive, 0})
    {:noreply, %State{state | peers: peers}}
  end

  defp tasks_mod() do
    Application.get_env(:wakesiah, :task_mod, Wakesiah.Tasks)
  end

end
