install-Module -Name SqlServer -AllowClobber
Start-Process msiexec.exe -Wait -ArgumentList "/I $env:userprofile\Documents\CD\Setup\DacFrameWork.msi"
copy-item $env:userprofile\Documents\CD\Setup\.ssh\id_rsa $env:userprofile\.ssh
Set-Service -Name ssh-agent -StartupType 'Manual'
Start-Service ssh-agent
ssh-add