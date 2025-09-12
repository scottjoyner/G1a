<#
.SYNOPSIS
  Switch CRC (OpenShift Local) resource profiles on HP ZBook

.DESCRIPTION
  Provides two profiles:
    - dev   → lighter footprint (12 GB RAM, 6 vCPUs, 80 GB disk)
    - full  → full lab setup (20 GB RAM, 8 vCPUs, 100 GB disk)

.EXAMPLE
  .\crc-profile.ps1 dev
  .\crc-profile.ps1 full
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "full")]
    [string]$Profile
)

function Set-CrcProfile {
    param (
        [string]$Name,
        [int]$Memory,
        [int]$CPUs,
        [int]$DiskSize
    )

    Write-Host "🔧 Applying CRC profile: $Name" -ForegroundColor Cyan
    crc config set memory $Memory   | Out-Null
    crc config set cpus $CPUs       | Out-Null
    crc config set disk-size $DiskSize | Out-Null
    Write-Host "✅ Profile '$Name' applied → ${Memory}MB RAM, ${CPUs} vCPUs, ${DiskSize}GB disk"
    Write-Host "👉 Run 'crc start' to boot the cluster with this config"
}

switch ($Profile) {
    "dev" {
        Set-CrcProfile -Name "Dev (Light)" -Memory 12000 -CPUs 6 -DiskSize 80
    }
    "full" {
        Set-CrcProfile -Name "Full Lab" -Memory 20000 -CPUs 8 -DiskSize 100
    }
}
