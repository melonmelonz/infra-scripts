# setup.ps1 — runs once at first logon inside the windows-main VM (as admin).
# Installs virtio drivers + QEMU guest agent, enables RDP and OpenSSH so the
# rest of provisioning (NVIDIA, Sunshine) can be driven remotely from sietch.
Start-Transcript -Path C:\setup-log.txt -Append

# --- Find the virtio-win CD by label ---------------------------------------
$virtio = $null
foreach ($v in Get-Volume) {
    if ($v.FileSystemLabel -like 'virtio-win*') { $virtio = $v.DriveLetter }
}

if ($virtio) {
    Write-Output "virtio CD at $($virtio):"
    # All virtio drivers (net, scsi, balloon, qxl, ...) silently.
    Start-Process msiexec.exe -ArgumentList "/i $($virtio):\virtio-win-gt-x64.msi /qn /norestart" -Wait
    # QEMU guest agent (lets Proxmox see the IP, clean shutdown, fs-freeze).
    Start-Process msiexec.exe -ArgumentList "/i $($virtio):\guest-agent\qemu-ga-x86_64.msi /qn /norestart" -Wait
} else {
    Write-Output "WARNING: virtio CD not found"
}

# --- RDP --------------------------------------------------------------------
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

# --- OpenSSH server (provisioning channel from the host) --------------------
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
# Make PowerShell the default SSH shell.
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

# --- Network: private profile so discovery/firewall behave -----------------
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# --- Power: this is a workstation-by-wire; never sleep ----------------------
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /hibernate off

Write-Output "setup.ps1 complete"
Stop-Transcript
