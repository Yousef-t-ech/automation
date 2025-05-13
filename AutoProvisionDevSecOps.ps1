param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$repositoryName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$projectName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$layerName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$componentName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$pat
)

function Get-ProjectId {
    param ([string]$projectName)
    try {
        $projectId = az devops project show --project $projectName --query "id" -o tsv
        if (-not $projectId) { throw "Project ID not found." }
        return $projectId
    } catch {
        Write-Output "Failed to get Project ID: $_"
        exit 1
    }
}

function Get-RepoId {
    param ([string]$projectName, [string]$repositoryName)
    try {
        $repoId = az repos show --project $projectName --repository $repositoryName --query "id" -o tsv
        if (-not $repoId) { throw "Repository ID not found." }
        return $repoId
    } catch {
        Write-Output "Failed to get Repository ID: $_"
        exit 1
    }
}


function Get-PolicyData {
    param (
        [string]$branch,
        [string]$org,
        [string]$project,
        [string]$repositoryId
    )
    $jsonData = az repos policy list --branch $branch --org $org --project $project --repository-id $repositoryId
    return $jsonData
}

function Map-Policies {
    param (
        [object[]]$jsonData,
        [hashtable]$policyMapping
    )
    [object[]]$resultArray = @()
    
    foreach ($uiPolicyName in $policyMapping.Keys) {
        # Get the scripting policy name mapped to the UI policy name
        $scriptingPolicyName = $policyMapping[$uiPolicyName]
        # Find all items in jsonData that match the current UI policy name
        $filteredItems = $jsonData | Where-Object { $_.type.displayName -eq $uiPolicyName }
        # Collect the IDs of the filtered items
        $ids = $filteredItems | ForEach-Object { $_.id }
        if ($scriptingPolicyName -and $ids.Count -gt 0) {
            $newItem = [pscustomobject]@{
                name = $scriptingPolicyName
                id = $ids -join ", "
            }
            $resultArray += $newItem
        }
        
    }
    return $resultArray
}

function Update-Policy {
    param (
        [array]$resultArray,
        [string]$repositoryId,
        [string]$branch,
        [string]$project,
        [string]$org,
        [switch]$enable
    )

    if ($enable) {
        foreach ($command in $resultArray) {
            $name = $command.name
            if ($name -eq "required-reviewer" -and $command.id) {
                $numbers = $command.id -split ', ' | ForEach-Object { [int]$_ }
                #$id in $command.id
                foreach ($id in $numbers) {
                    Write-Debug "Updating policy ID: $id"
                    az repos policy $name update --enable true --id $id --repository-id $repositoryId --branch $branch --project $project --organization $org
                }
            } else {
                az repos policy $name update --enable true --id $($command.id) --repository-id $repositoryId --branch $branch --project $project --organization $org
            }
        }
    } else {
        foreach ($command in $resultArray) {
            $name = $command.name
            if ($name -eq "required-reviewer" -and $command.id) {
                $numbers = $command.id -split ', ' | ForEach-Object { [int]$_ }
                #$id in $command.id
                foreach ($id in $numbers) {
                    Write-Debug "Updating policy ID: $id"
                    az repos policy $name update --enable false --id $id --repository-id $repositoryId --branch $branch --project $project --organization $org
                }
            } else {
                az repos policy $name update --enable false --id $($command.id) --repository-id $repositoryId --branch $branch --project $project --organization $org
            }
        }
    }

}

function Disable-Enable-BranchPolicies {
    param ([object[]]$resultArray,[string]$repoId, [string]$projectName, [string]$org, [switch]$enable)

    if ($enable){
        Update-Policy -resultArray $resultArray -repositoryId $repoId -branch $branchName -project $projectName -org $org -enable $true
    } else {
        Update-Policy -resultArray $resultArray -repositoryId $repoId -branch $branchName -project $projectName -org $org
    }
}

function ConvertToUtf16Hex {
    param ([string]$text)
    $encodedText = ""
    foreach ($char in $text.ToCharArray()) {
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($char)
        $encodedText += "{0:X2}{1:X2}" -f $bytes[0], $bytes[1]
    }
    return $encodedText
}

function Disable-Enable-ContributorGroup {
    param (
        [string]$projectId,
        [string]$repoId,
        [string]$branchName,
        [string]$projectName,
        [string]$org,
        [switch]$enable
    )
    try {
        $encodedBranchName = ConvertToUtf16Hex -text $branchName
        $securityNamespace = az devops security permission namespace list --query "[?name=='Git Repositories'].namespaceId" --output tsv
        $securityToken = "repoV2/$projectId/$repoId/refs/heads/$encodedBranchName"
        $contributorsGroup = az devops security group list --project $projectName --organization $org --query "graphGroups[?displayName=='Contributors'].descriptor" -o tsv
        if ($enable) {
            az devops security permission update --id $securityNamespace --subject $contributorsGroup --token $securityToken --allow-bit 4 --organization $org --merge false
            Write-Output "Contributor group permissions enabled successfully."
        } else {
            az devops security permission update --id $securityNamespace --subject $contributorsGroup --token $securityToken --deny-bit 4 --organization $org --merge false
            Write-Output "Contributor group permissions disabled successfully."
        }
    } catch {
        Write-Output "Failed to update Contributor group permissions: $_"
    }
}

function Clone-Repos {
    param ([string]$pat, [string]$projectName, [string]$repositoryName)
    try {
        git clone -b main --single-branch https://$pat@dev.azure.com/ThiqahDev/DevOps/_git/TemplatesFiles
        git clone -b develop --single-branch https://$pat@dev.azure.com/ThiqahDev/$projectName/_git/$repositoryName
        git clone https://$pat@dev.azure.com/ThiqahDev/$projectName/_git/Pipelines
        Write-Output "Repositories cloned successfully."
    } catch {
        Write-Output "Failed to clone repositories: $_"
        exit 1
    }
}

function Create-PipelineFolders {
    param ([string]$repositoryName, [string]$componentName)
    #mkdir ./$repositoryName/Pipeline/$componentName
    if (-not (Test-Path -Path "./$repositoryName/Pipeline/$componentName")) {
        mkdir "./$repositoryName/Pipeline/$componentName"
    } else {
        Write-Output "Directory './$repositoryName/Pipeline/$componentName' already exists. Skipping creation."
    }
    mkdir ./Pipelines/$componentName-v2.1
}

function Copy-Files {
    param ([string]$layerName, [string]$repositoryName, [string]$componentName)
    if ($layerName -eq "Frontend") {
        Copy-Item -Path "./TemplatesFiles/Continuous Integration (CI)/Frontend-CI.yaml" -Destination "./$repositoryName/Pipeline/$componentName/"
        Copy-Item -Path "./TemplatesFiles/Variables/Frontend-variables.yaml" -Destination "./$repositoryName/Pipeline/$componentName/"
        Copy-Item -Path "./TemplatesFiles/Continuous Deployment (CD)/Frontend-CD.yaml" -Destination "./Pipelines/$componentName-v2.1"
        Copy-Item -Path "./TemplatesFiles/Variables/pre-prod-variables.yaml" -Destination "./Pipelines/$componentName-v2.1"
        Copy-Item -Path "./TemplatesFiles/Variables/test-variables.yaml" -Destination "./Pipelines/$componentName-v2.1"
        if ($componentName -ine "Frontend") {
            Rename-Item -Path "./$repositoryName/Pipeline/$componentName/Frontend-CI.yaml" -NewName "$componentName-CI.yaml"
            Rename-Item -Path "./$repositoryName/Pipeline/$componentName/Frontend-variables.yaml" -NewName "$componentName-variables.yaml"
            Rename-Item -Path "./Pipelines/$componentName-v2.1/Frontend-CD.yaml" -NewName "$componentName-CD.yaml"
        }
    } elseif ($layerName -eq "Backend") {
        Copy-Item -Path "./TemplatesFiles/Continuous Integration (CI)/Backend-CI.yaml" -Destination "./$repositoryName/Pipeline/$componentName/"
        Copy-Item -Path "./TemplatesFiles/Variables/Backend-variables.yaml" -Destination "./$repositoryName/Pipeline/$componentName/"
        Copy-Item -Path "./TemplatesFiles/Continuous Deployment (CD)/Backend-CD.yaml" -Destination "./Pipelines/$componentName-v2.1"
        Copy-Item -Path "./TemplatesFiles/Variables/pre-prod-variables.yaml" -Destination "./Pipelines/$componentName-v2.1"
        Copy-Item -Path "./TemplatesFiles/Variables/test-variables.yaml" -Destination "./Pipelines/$componentName-v2.1"
        Rename-Item -Path "./$repositoryName/Pipeline/$componentName/Backend-CI.yaml" -NewName "$componentName-CI.yaml"
        Rename-Item -Path "./$repositoryName/Pipeline/$componentName/Backend-variables.yaml" -NewName "$componentName-variables.yaml"
        Rename-Item -Path "./Pipelines/$componentName-v2.1/Backend-CD.yaml" -NewName "$componentName-CD.yaml"
    }
}
function Change-Variables-Names{
    param ([string]$repositoryName, [string]$componentName)
    $filePath = "./$repositoryName/Pipeline/$componentName/$componentName-CI.yaml"
    $content = Get-Content -Path $filePath
    $newTemplateLine = "  - template: $componentName-variables.yml #ex. $componentName-variables.yml"
    for ($i = 0; $i -lt $content.Length; $i++) {
        if ($content[$i] -match "\s+- template:\s+\[component\]-variables.yml\s+#ex\. Backend-variables.yml") {
            $content[$i] = $newTemplateLine
            break
        }
    }
    Set-Content -Path $filePath -Value $content
    Write-Output "Updated 'template' line in $filePath successfully."
}
function Push-Changes {
    param ([string]$repositoryName, [string]$componentName, [string]$layerName)
    $email = "a.ymutairi@dev.thiqah.sa"
    $name = "Yousef K. Almutairi"
    if ($layerName -eq "Frontend") {
        Set-Location ./$repositoryName/
        git config user.email $email
        git config user.name $name
        git add .
        git commit -m 'Added Frontend-CI.yaml, Frontend-variables.yaml'
        git push origin HEAD
        Set-Location ..
        Set-Location ./Pipelines/$componentName-v2.1
        git config user.email $email
        git config user.name $name
        git add .
        git commit -m 'Added Frontend-CD.yaml, pre-prod-variables.yaml & test-variables.yaml'
        git push origin HEAD
        Set-Location ../..
    } elseif ($layerName -eq "Backend") {
        Set-Location ./$repositoryName/
        git config user.email $email
        git config user.name $name
        git add .
        git commit -m 'Added Backend-CI.yaml, Backend-variables.yaml'
        git push origin HEAD
        Set-Location ..
        Set-Location ./Pipelines/$componentName-v2.1
        git config user.email $email
        git config user.name $name
        git add .
        git commit -m 'Added Backend-CD.yaml, pre-prod-variables.yaml & test-variables.yaml'
        git push origin HEAD
        Set-Location ../..
    }
}

function Create-Pipelines {
    param ([string]$repositoryName, [string]$componentName, [string]$projectName, [string]$pipelineBranch)
    try {
        $null = az pipelines create --name "$componentName-CI" --repository "$repositoryName" --branch "develop" --repository-type "tfsgit" --yml-path "Pipeline/$componentName/$componentName-CI.yaml" --project "$projectName" --skip-first-run --output json
        Write-Output "$componentName-CI Pipeline created successfully."
    } catch {
        Write-Output "$componentName-CI Pipeline creation failed: $_"
    }
    try {
        # Fix the yml-path - remove the Pipeline/ 
        $null = az pipelines create --name "$componentName-CD" --repository "Pipelines" --branch $pipelineBranch --repository-type "tfsgit" --yml-path "$componentName-v2.1/$componentName-CD.yaml" --project "$projectName" --skip-first-run --output json
        Write-Output "$componentName-CD Pipeline created successfully."
    } catch {
        Write-Output "$componentName-CD Pipeline creation failed: $_"
    }
}

# 1/ prepare steps 
$org = "https://dev.azure.com/ThiqahDev"
$branchName = "develop"
$env:AZURE_DEVOPS_EXT_PAT = $pat
$projectId = Get-ProjectId -projectName $projectName
$repoId = Get-RepoId -projectName $projectName -repositoryName $repositoryName
# Define the mapping between UI policy names and scripting policy names
$policyMapping = @{
    "Minimum number of reviewers" = "approver-count"
    "Work item linking" = "work-item-linking"
    "Comment requirements" = "comment-required"
    "Require a merge strategy" = "merge-strategy"
    "Required reviewers" = "required-reviewer"
}
# Get policy data
$jsonData = Get-PolicyData -branch $branchName -org $org -project $projectName -repositoryId $repoId
$jsonData = $jsonData | ConvertFrom-Json
# Map policies
$resultArray = Map-Policies -jsonData $jsonData -policyMapping $policyMapping

# 2/ add pipeline files to the Source Code Repo & Pipeline Repo
Clone-Repos -pat $pat -projectName $projectName -repositoryName $repositoryName
Create-PipelineFolders -repositoryName $repositoryName -componentName $componentName
Copy-Files -layerName $layerName -repositoryName $repositoryName -componentName $componentName

# 3/ disable branch policies & contributor group contribute permission on develop branch & push changes to remote repo
Disable-Enable-BranchPolicies -resultArray $resultArray -repoId $repoId -projectName $projectName -org $org -enable:$false
Disable-Enable-ContributorGroup -projectId $projectId -repoId $repoId -branchName $branchName -projectName $projectName -org $org -enable:$false
Push-Changes -repositoryName $repositoryName -componentName $componentName -layerName $layerName

# 4/ enable branch policies & contributor group contribute permission on develop branch
Disable-Enable-BranchPolicies -resultArray $resultArray -repoId $repoId -projectName $projectName -org $org -enable:$true
Disable-Enable-ContributorGroup -projectId $projectId -repoId $repoId -branchName $branchName -projectName $projectName -org $org -enable:$true

# 5/ enable branch policies & contributor group contribute permission on develop branch
$pipelineBranch = (git -C ./Pipelines rev-parse --abbrev-ref HEAD)
Create-Pipelines -repositoryName $repositoryName -componentName $componentName -projectName $projectName -pipelineBranch $pipelineBranch

# 6/ delete local repositories
Write-Output "Deleting local repositories..."
Remove-Item -Path "./Pipelines" -Recurse -Force
Remove-Item -Path "./TemplatesFiles" -Recurse -Force
Remove-Item -Path "./$($repositoryName)" -Recurse -Force
Write-Output "Done."
