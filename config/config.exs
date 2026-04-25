import Config

config :git_ops,
  mix_project: LightCDP.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/lessless/light_cdp",
  manage_mix_version?: true,
  manage_readme_version: false,
  version_tag_prefix: "v"

import_config "#{config_env()}.exs"
