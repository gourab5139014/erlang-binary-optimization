defmodule ErlangBinaryOptimization.MixProject do
  use Mix.Project

  def project do
    [
      app: :erlang_binary_optimization,
      version: "0.1.0",
      elixir: "~> 1.14",
      erlc_paths: ["src"],
      deps: deps()
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.3", only: :dev}
    ]
  end
end
