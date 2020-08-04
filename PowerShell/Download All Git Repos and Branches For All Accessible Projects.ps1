$OutputFilePath = "C:\Temp\" + (Get-Date).ToString("yyyy-MM-dd") + "-code.zip"
$IgnoreOrganizations = @("")
$IgnoreProjects = @()           # Ignored project names need to only be included if they are unique across all organizations
$IgnoreRepositories = @()       # Ignored repositories need to be only included if they are unique across all organizations and projects
$Debug = $false                 # Set to $true to skip actual processing and only show debug information
$DebugGroupedOutput = $false    # Set to $true to output collections instead of single items. Requires $Debug = $true
$ZipFie = $false                # Set to true to zip the file to $OutputFilePath
$DefaultTempPath = [System.IO.Path]::GetTempPath()

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
$TempFolder = ''
$ApiKey = ''
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ApiKey)")) }
$UriApiVersionSuffix = '?api-version=5.1'

function GetUserId(){
    $UriProfileInformation = "https://app.vssps.visualstudio.com/_apis/profile/profiles/me$($UriApiVersionSuffix)"
    $response = Invoke-RestMethod $UriProfileInformation -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response.id
}

function GetOrganizationList([string] $userId){
    $UriAccountList = "https://app.vssps.visualstudio.com/_apis/accounts" + $UriApiVersionSuffix + "&memberId=" + $userId
    $response = Invoke-RestMethod $UriAccountList -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response.value
}

function GetProjectList([string] $organizationName){
    $UriProjectList = "https://dev.azure.com/$($OrganizationName)/_apis/projects$($UriApiVersionSuffix)"
    $response = Invoke-RestMethod $UriProjectList -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response
}

function GetGitRepositories([string] $organizationName, [string] $projectName){
    $UriGitRepositories = "https://dev.azure.com/$($organizationName)/$($projectName)/_apis/git/repositories$($UriApiVersionSuffix)"
    $response = Invoke-RestMethod $UriGitRepositories -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response
}

function GetGitBranches([string] $organizationName, [string] $projectName, [string] $repositoryId){
    $UriGitBranches = "https://dev.azure.com/$($organizationName)/$($projectName)/_apis/git/repositories/$($repositoryId)/refs$($UriApiVersionSuffix)&filter=heads/"
    $response = Invoke-RestMethod $UriGitBranches -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response
}

function New-TemporaryDirectory {
    $parent = $DefaultTempPath
    $name = [System.IO.Path]::GetRandomFileName()
    if ($Debug -eq $false)
    {
        New-Item -ItemType Directory -Path (Join-Path $parent $name)
    }
}

$TempFolder = New-TemporaryDirectory
if ($Debug -eq $false)
{
    Write-Host "Temp folder is" $TempFolder
}

$UserId = GetUserId
$Organizations = GetOrganizationList($UserId)

if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
    $Organizations | Format-Table | Out-String | Write-Host
}

foreach ($organization in $Organizations) {
    
    if ($IgnoreOrganizations.Contains($organization.accountName)){
         continue;
    }
    
    if ($Debug -eq $true -and $DebugGroupedOutput -eq $false){
        $organization | Format-Table | Out-String | Write-Host
    }
    
    $projects = GetProjectList $organization.accountName
    
    if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
        $projects.value | Format-Table | Out-String | Write-Host
    }

    foreach ($project in $projects.value) {
        if ($IgnoreProjects.Contains($project.name)){
            continue;
        }

        if ($Debug -eq $true -and $DebugGroupedOutput -eq $false){
            $project | Format-Table | Out-String | Write-Host
        }

        $repositories = GetGitRepositories $organization.accountName $project.name
        
        if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
            $repositories.value | Format-Table | Out-String | Write-Host
        }

        foreach ($repository in $repositories.value) {
            if ($IgnoreRepositories.Contains($repository.name)){
                continue;
            }
            
            if ($Debug -eq $true -and $DebugGroupedOutput -eq $false){
                $repository | Format-Table | Out-String | Write-Host
            }

            $repositoryFullPath = $TempFolder.FullName + "\" + $organization.accountName + "\" + $project.name  + "\" + $repository.name
            
            if ($Debug -eq $false)
            {
                git clone $repository.webUrl $repositoryFullPath
                Set-Location $repositoryFullPath
            }

            $branches = GetGitBranches $organization.accountName $project.name $repository.id

            if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
                $branches.value | Format-Table | Out-String | Write-Host
            }

            foreach ($branch in $branches.value) {
                $branchName = $branch.name.Replace("refs/heads/","")
                if ($Debug -eq $true -and $DebugGroupedOutput -eq $false){
                    $branch | Format-Table | Out-String | Write-Host
                }

                if ($Debug -eq $false)
                {
                    git checkout $branchName
                }                                
            }
            if ($Debug -eq $false){
                git switch master
            }
        }
    }
}

if ($Debug -eq $false -and $ZipFie -eq $true){
    Compress-Archive -Path "$($TempFolder)\*" -DestinationPath $OutputFilePath
    Write-Host "Downloaded all organizations repository branches in" $stopwatch.Elapsed "file located at '"$OutputFilePath"'"
}
elseif ($Debug -eq $false){
    # Move out of the folder we wrote everything to so we can move/rename the folder
    Set-Location "C:\Temp"
    $OutputFolder = [System.IO.Path]::GetDirectoryName($OutputFilePath) + "\" + [System.IO.Path]::GetFileNameWithoutExtension($OutputFilePath)
    $TempFolderPath = $TempFolder.FullName

    Write-Host "Moving folder from '"$TempFolderPath"' to '"$OutputFolder"'"

    Move-Item -Path $TempFolderPath -Destination $OutputFolder
    
    $stopwatch.Stop();

    Write-Host "Downloaded all organizations repository branches in" $stopwatch.Elapsed "to the folder '"$OutputFolder"'"
}
elseif ($Debug -eq $true){
    Write-Host "Debug run completed in" $stopwatch.Elapsed
}
