locals {
  # AML managed virtual network outbound rules to allow for VS Code SSH connectivity to Compute Instances
  vscode_ssh_outbound_fqdn_rules = {
          AllowVsCodeDevWildcard = {
            type        = "FQDN"
            destination = "*.vscode.dev"
            category    = "UserDefined"
          }
          AllowVsCodeBlob = {
            type        = "FQDN"
            destination = "vscode.blob.core.windows.net"
            category    = "UserDefined"
          }
          AllowGalleryCdnWildcard = {
            type        = "FQDN"
            destination = "*.gallerycdn.vsassets.io"
            category    = "UserDefined"
          }
          AllowRawGithub = {
            type        = "FQDN"
            destination = "raw.githubusercontent.com"
            category    = "UserDefined"
          }
          AllowVsCodeUnpkWildcard = {
            type        = "FQDN"
            destination = "*.vscode-unpkg.net"
            category    = "UserDefined"
          }
          AllowVsCodeCndWildcard = {
            type        = "FQDN"
            destination = "*.vscode-cdn.net"
            category    = "UserDefined"
          }
          AllowVsCodeExperimentsWildcard = {
            type        = "FQDN"
            destination = "*.vscodeexperiments.azureedge.net"
            category    = "UserDefined"
          }
          AllowDefaultExpTas = {
            type        = "FQDN"
            destination = "default.exp-tas.com"
            category    = "UserDefined"
          }
          AllowCodeVisualStudio = {
            type        = "FQDN"
            destination = "code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowUpdateCodeVisualStudio = {
            type        = "FQDN"
            destination = "update.code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsMsecndNet = {
            type        = "FQDN"
            destination = "*.vo.msecnd.net"
            category    = "UserDefined"
          }
          AllowMarketplaceVisualStudio = {
            type        = "FQDN"
            destination = "marketplace.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsCodeDownload = {
            type        = "FQDN"
            destination = "vscode.download.prss.microsoft.com"
            category    = "UserDefined"
          }
  }

  # AML managed virtual network outbound rules to allow access to Python package index
  python_library_outbound_fqdn_rules = {
    AllowPypi = {
      type        = "FQDN"
      destination = "pypi.org"
      category    = "UserDefined"
    }
    AllowPythonHostedWildcard = {
      type        = "FQDN"
      destination = "*.pythonhosted.org"
      category    = "UserDefined"
    }
  }

  # AML managed virtual network outbound rules to allow access to Anaconda packages
  conda_library_outbound_fqdn_rules = {
    AllowAnacondaCom = {
      type        = "FQDN"
      destination = "anaconda.com"
      category    = "UserDefined"
    }
    AllowAnacondaComWildcard = {
      type        = "FQDN"
      destination = "*.anaconda.com"
      category    = "UserDefined"
    }
    AllowAnacondaOrgWildcard = {
      type        = "FQDN"
      destination = "*.anaconda.org"
      category    = "UserDefined"
    }
  }

  # AML managed virtual network outbound rules to allow access to Docker Hub
  docker_outbound_fqdn_rules = {
    AllowDockerIo = {
      type        = "FQDN"
      destination = "docker.io"
      category    = "UserDefined"
    }
    AllowDockerIoWildcard = {
      type        = "FQDN"
      destination = "*.docker.io"
      category    = "UserDefined"
    }
    AllowDockerComWildcard = {
      type        = "FQDN"
      destination = "*.docker.com"
      category    = "UserDefined"
    }
    AllowDockerCloudFlareProduction = {
      type        = "FQDN"
      destination = "production.cloudflare.docker.com"
      category    = "UserDefined"
    }
  }

  # AML managed virtual network outbound rules to allow access to HuggingFace models
  huggingface_outbound_fqdn_rules = {
    AllowCdnAuth0Com = {
      type        = "FQDN"
      destination = "cdn.auth0.com"
      category    = "UserDefined"
    }
    AllowCdnHuggingFaceCo = {
      type        = "FQDN"
      destination = "cdn-lfs.huggingface.co"
      category    = "UserDefined"
    }
  }

  # AML managed virtual network outbound rules that are special to this lab environment
  user_defined_outbound_fqdn_rules = {
    AllowSampleFiles = {
      type        = "FQDN"
      destination = "github.com"
      category    = "UserDefined"
    }
  }

  # AML managed virtual network outbound rules defined in variable for the template
  user_defined_outbound_pe_rules = {
    for k, v in var.user_defined_outbound_rules_private_endpoint_resources : 
    k => {
      category = "UserDefined"
      type     = "PrivateEndpoint"
      destination = {
        serviceResourceId  = v.serviceResourceId
        subresourceTarget  = v.subresourceTarget
      }
    }
  }
}
