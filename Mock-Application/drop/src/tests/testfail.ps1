Write-Host "Name: $Env:AGENT_NAME."
Write-Host "ID: $Env:AGENT_ID."
write-error "should fail"
exit 1