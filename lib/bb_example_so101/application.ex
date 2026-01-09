defmodule BB.Example.SO101.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BB.Example.SO101Web.Telemetry,
        {DNSCluster,
         query: Application.get_env(:bb_example_so101, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BB.Example.SO101.PubSub},
        BB.Example.SO101Web.Endpoint
      ] ++ robot_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BB.Example.SO101.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BB.Example.SO101Web.Endpoint.config_change(changed, removed)
    :ok
  end

  defp robot_children do
    if Application.get_env(:bb_example_so101, :start_robot, true) do
      [{BB.Example.SO101.Robot, robot_opts()}]
    else
      []
    end
  end

  defp robot_opts do
    if System.get_env("SIMULATE") do
      [simulation: :kinematic]
    else
      []
    end
  end
end
