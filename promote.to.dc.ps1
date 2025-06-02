configuration ConfigureDomainController {
    param (
        [string]$DomainName,
        [string]$DnsServerIP,
        [PSCredential]$AdminCreds,
        [string]$SafeModePassword
    )

    # Ensure required modules are available
    Script InstallDscModules {
        GetScript  = { @{ Result = "Check DSC modules" } }
        TestScript = {
            (Get-Module -Name xActiveDirectory -ListAvailable) -and
            (Get-Module -Name xDnsServer -ListAvailable)
        }
        SetScript  = {
            Install-Module -Name xActiveDirectory -Force -AllowClobber
            Install-Module -Name xDnsServer -Force -AllowClobber
            Import-Module -Name xActiveDirectory, xDnsServer -Force
        }
    }

    Node localhost {
        # Install DSC Modules if missing
        Script InstallDscModules {
            GetScript  = { @{ Result = "Check DSC modules" } }
            TestScript = {
                (Get-Module -Name xActiveDirectory -ListAvailable) -and
                (Get-Module -Name xDnsServer -ListAvailable)
            }
            SetScript  = {
                Install-Module -Name xActiveDirectory -Force -AllowClobber
                Install-Module -Name xDnsServer -Force -AllowClobber
            }
        }

        # Install DNS Server Role
        WindowsFeature DNS {
            Ensure    = 'Present'
            Name      = 'DNS'
            DependsOn = '[Script]InstallDscModules'
        }

        # Configure DNS Server
        xDnsServerAddress DnsConfig {
            Address        = $DnsServerIP
            InterfaceAlias = 'Ethernet'
            AddressFamily  = 'IPv4'
            DependsOn      = '[WindowsFeature]DNS'
        }

        # Install AD DS Role
        WindowsFeature ADDS {
            Ensure    = 'Present'
            Name      = 'AD-Domain-Services'
            DependsOn = '[WindowsFeature]DNS'
        }

        # Promote to Domain Controller
        xADDomainController DomainController {
            DomainName                    = $DomainName
            DomainAdministratorCredential  = $AdminCreds
            SafemodeAdministratorPassword  = (ConvertTo-SecureString $SafeModePassword -AsPlainText -Force)
            DependsOn                     = '[WindowsFeature]ADDS', '[xDnsServerAddress]DnsConfig'
        }
    }
}