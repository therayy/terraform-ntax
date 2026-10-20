output "team_mounts" {
  description = "KV mount created for each team."
  value = {
    for team_name, team_module in module.team_config :
    team_name => team_module.mount_path
  }
}