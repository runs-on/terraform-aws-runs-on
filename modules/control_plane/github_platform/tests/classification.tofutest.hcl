run "empty_base_url_is_github_com" {
  command = plan

  variables {
    base_url = ""
  }

  assert {
    condition     = output.platform == "github.com" && output.enterprise_url == "" && output.base_url == "https://github.com"
    error_message = "An empty base URL should classify as github.com."
  }

  assert {
    condition     = output.token_issuer == "https://token.actions.githubusercontent.com"
    error_message = "github.com should use the fixed Actions OIDC issuer."
  }
}

run "github_com_with_port_is_github_com" {
  command = plan

  variables {
    base_url = "https://github.com:443/"
  }

  assert {
    condition     = output.platform == "github.com" && output.base_url == "https://github.com"
    error_message = "github.com with an explicit port should classify as github.com."
  }
}

run "ghe_com_with_port_keeps_data_residency_classification" {
  command = plan

  variables {
    base_url = "https://sttnwrks.ghe.com:443"
  }

  assert {
    condition     = output.platform == "ghe.com" && output.enterprise_url == "https://sttnwrks.ghe.com"
    error_message = "A GHE.com host with an explicit port should classify as GHE.com with the port dropped."
  }

  assert {
    condition     = output.token_issuer == "https://token.actions.sttnwrks.ghe.com"
    error_message = "A GHE.com host with an explicit port should use the tenant Actions OIDC issuer."
  }
}

run "ghe_com_api_host_with_port_and_api_path" {
  command = plan

  variables {
    base_url = "https://api.sttnwrks.ghe.com:443/api/v3"
  }

  assert {
    condition     = output.platform == "ghe.com" && output.enterprise_url == "https://sttnwrks.ghe.com"
    error_message = "A GHE.com API host with a port and /api/v3 path should still classify as GHE.com."
  }
}

run "ghes_with_custom_port_keeps_port" {
  command = plan

  variables {
    base_url = "https://ghe.example.com:8443/api/v3/"
  }

  assert {
    condition     = output.platform == "ghes" && output.enterprise_url == "https://ghe.example.com:8443"
    error_message = "A GHES host should keep its custom port with the /api/v3 path stripped."
  }

  assert {
    condition     = output.token_issuer == "https://ghe.example.com:8443/_services/token"
    error_message = "A GHES host should derive its issuer from the port-preserving host root."
  }
}
