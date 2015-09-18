use Mix.Config

config :logger, :console, level: :info,
  format: "$date $time [$level] $message\n"

import_config "#{Mix.env}.exs"
