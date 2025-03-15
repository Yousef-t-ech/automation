
param(
    [string]$PAT,
    [string]$agentPool,
    [string]$devOpsUrl
)
try {
    #Set-ExecutionPolicy Bypass -Scope Process -Force
    Start-Transcript -Path "C:\\agent\\install-agent.log" -Append
    # Azure DevOps details
    #v4.253.0
    #"3.220.5"
    $agentVersion = "4.253.0"
    $agentName = "TestingTerraformAgent"
    $agentDir = "C:\\agent"
    # Ensure the agent directory exists
    if (!(Test-Path $agentDir)) {
        New-Item -ItemType Directory -Path $agentDir -Force
    }

    # Download agent
    Write-Host "Downloading Azure DevOps Agent..."
    Invoke-WebRequest -Uri ("https://vstsagentpackage.azureedge.net/agent/{0}/vsts-agent-win-x64-{0}.zip" -f $agentVersion) `
        -OutFile ("{0}\\agent.zip" -f $agentDir) -UseBasicParsing

    # Check if the download was successful
    if (!(Test-Path ("{0}\\agent.zip" -f $agentDir))) {
        Write-Error "Failed to download Azure DevOps agent."
        exit 1
    }

    # Extract agent
    Write-Host "Extracting Azure DevOps Agent..."
    Expand-Archive -Path ("{0}\\agent.zip" -f $agentDir) -DestinationPath $agentDir -Force

    # Navigate to the agent directory
    Set-Location -Path $agentDir

    # Check if agent is already configured
    if (Test-Path ("{0}\\.agent" -f $agentDir)) {
        Write-Host "Agent already configured, skipping configuration."
    } else {
        Write-Host ("PAT is :{0}" -f $PAT)
        Write-Host("agentPool is :{0}" -f $agentPool)
        Write-Host "Configuring agent..."
        .\\config.cmd --replace --unattended --url $devOpsUrl --auth pat --token $PAT --pool $agentPool --agent $agentName --runAsService
        Write-Host "Agent configured successfully."
        exit 0
    }
    

} catch {
    Write-Host "We are in the catch block"
    Write-Error ("An error occurred: {0}" -f $_)
    exit 1
}
exit 0
Stop-Transcript