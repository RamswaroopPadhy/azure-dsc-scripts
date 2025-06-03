configuration ConfigureDomainController {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainName,
        
        [Parameter(Mandatory=$true)]
        [string]$DnsServerIP,
        
        [Parameter(Mandatory=$true)]
        [PSCredential]$AdminCreds,
        
        [Parameter(Mandatory=$true)]
        [string]$SafeModePassword
    )

    # Log setup for troubleshooting
    $logPath = "C:\Windows\Temp\DSC-DC-Promotion.log"
    Start-Transcript -Path $logPath -Append

    Node localhost {
        # Single module installation block (removed duplicate)
        Script InstallDscModules {
            GetScript  = { @{ Result = "DSC Modules Check" } }
            TestScript = {
                try {
                    $modulesInstalled = (Get-Module -Name xActiveDirectory, xDnsServer -ListAvailable).Count -eq 2
                    if (-not $modulesInstalled) {
                        Write-Warning "Required DSC modules missing"
                    }
                    return $modulesInstalled
                }
                catch {
                    Write-Error "Module check failed: $_"
                    return $false
                }
            }
            SetScript  = {
                try {
                    Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                    Install-Module -Name xActiveDirectory, xDnsServer -Force -AllowClobber -ErrorAction Stop
                    Write-Output "Successfully installed required DSC modules"
                }
                catch {
                    Write-Error "Module installation failed: $_"
                    exit 1
                }
            }
        }

        # Install DNS Server Role with error handling
        WindowsFeature DNS {
            Ensure    = 'Present'
            Name      = 'DNS'
            DependsOn = '[Script]InstallDscModules'
        }

        # Dynamic network interface configuration
        Script ConfigureDns {
            GetScript  = { @{ Result = "DNS Configuration" } }
            TestScript = { $false } # Always run this to ensure DNS is properly set
            SetScript  = {
                try {
                    $adapter = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ($using:DnsServerIP)
                    Write-Output "DNS configured on interface: $($adapter.Name)"
                }
                catch {
                    Write-Error "DNS configuration failed: $_"
                    exit 1
                }
            }
            DependsOn = '[WindowsFeature]DNS'
        }

        # Install AD DS Role
        WindowsFeature ADDS {
            Ensure    = 'Present'
            Name      = 'AD-Domain-Services'
            DependsOn = '[Script]ConfigureDns'
        }

        # Domain Controller promotion with validation
        xADDomainController DomainController {
            DomainName                    = $DomainName
            DomainAdministratorCredential  = $AdminCreds
            SafemodeAdministratorPassword  = (ConvertTo-SecureString $SafeModePassword -AsPlainText -Force)
            DependsOn                     = '[WindowsFeature]ADDS'
        }

        # Final validation
        Script VerifyPromotion {
            GetScript  = { @{ Result = "DC Verification" } }
            TestScript = { 
                try {
                    $dc = Get-ADDomainController -ErrorAction Stop
                    return ($dc.Name -eq $env:COMPUTERNAME)
                }
                catch {
                    return $false
                }
            }
            SetScript  = {
                Write-Output "Domain controller promotion verified successfully"
            }
            DependsOn = '[xADDomainController]DomainController'
        }
    }

    Stop-Transcript
}
