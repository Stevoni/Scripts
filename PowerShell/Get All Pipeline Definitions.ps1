Clear-Host

# Todo: Update the debug output

$IgnoreOrganizations = @("")
$IgnoreProjects = @("")         # Ignored project names need to only be included if they are unique across all organizations
$Debug = $false                 # Set to $true to skip actual processing and only show debug information
$DebugGroupedOutput = $false    # Set to $true to output collections instead of single items. Requires $Debug = $true

$ApiKey = ''
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ApiKey)")) }

$UriApiVersionSuffix = '?api-version=6.0-preview.1'

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

function GetPipelineList([string] $organizationName, [string] $projectName){
    $UriPipelineList = "https://dev.azure.com/$($organizationName)/$($projectName)/_apis/pipelines$($UriApiVersionSuffix)"
    $response = Invoke-RestMethod $UriPipelineList -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    return $response
}

function GetPipeline([string] $organizationName, [string] $projectName, [string] $pipelineId){
    $UriPipelineList = "https://dev.azure.com/$($organizationName)/$($projectName)/_apis/pipelines/$($pipelineId)?api-version=6.0-preview.1"
    
    $response = Invoke-RestMethod $UriPipelineList -Method 'GET' -Headers $AzureDevOpsAuthenicationHeader
    
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

$UserId = GetUserId
$Organizations = GetOrganizationList($UserId)
$pipelines = @()

if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
    $Organizations | Format-Table | Out-String | Write-Host
}

$triggers = @()

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

        $pipelines = (GetPipelineList $organization.accountName $project.name) | Select-Object -ExpandProperty value
        
        # Todo: Update the folder exclusions to be a collection
        $pipelines = $pipelines | Where-Object {$_.folder -notlike '\Previous*' } | Select-Object 

        if ($Debug -eq $true -and $DebugGroupedOutput -eq $true){
            $pipelines | Select-Object | Format-Table | Out-String | Write-Host
        }

        foreach($pipeline in $pipelines){

            if ($Debug -eq $true -and $DebugGroupedOutput -eq $false){
                $pipeline | Format-Table | Out-String | Write-Host
            }
            
            # Todo: Update the pipeline exclusion to be a collection
            if ($pipeline.name -eq "Test Build Pipeline"){
                continue;
            }
            
            $pipelineDefinition = GetPipeline $organization.accountName $project.name $pipeline.id
    
            if (($pipelineDefinition.PSObject.Properties.Name -contains "configuration") -eq $false){
                Write-Host "missing configuration"
                $pipelineDefinition | Format-Table | Out-String | Write-Host
                continue;
            }
            elseif (($pipelineDefinition.configuration.PSObject.Properties.Name -contains "designerJson") -eq $false){
                $triggers += $pipelineDefinition | Select-Object @{name = "organization"; expression = {$organization.accountName}}, @{name = "project"; expression={$project.name}}, @{name="pipeline";expression={$pipeline.name}}, @{name="branchFilters"; expression=" "}, @{name="triggerType"; expression={"yaml"}}, @{name="schedule"; expression= " "}
                continue;
            }
            elseif (($pipelineDefinition.configuration.designerJson.PSObject.Properties.name -contains "triggers") -eq $false) {
                $triggers += $pipelineDefinition | Select-Object @{name = "organization"; expression = {$organization.accountName}}, @{name = "project"; expression={$project.name}}, @{name="pipeline";expression={$pipeline.name}}, @{name="branchFilters"; expression=" "}, @{name="triggerType"; expression={"none"}}, @{name="schedule"; expression= " "}
                continue;
            }

            $ciDefinition = $pipelineDefinition | Select-Object -ExpandProperty configuration | Select-Object -ExpandProperty designerJson | Select-Object -ExpandProperty triggers | Where-Object -Property triggerType -eq "continuousIntegration"

            $scheduleDefinition = $pipelineDefinition | Select-Object -ExpandProperty configuration | Select-Object -ExpandProperty designerJson | Select-Object -ExpandProperty triggers | Where-Object -Property triggerType -eq "schedule"
            
            $tempTriggers = @()
            $tempTriggers += $ciDefinition | Select-Object branchFilters, triggerType, @{name = "schedule"; expression = " "}
            $scheduleItem = $scheduleDefinition | Select-Object -ExpandProperty schedules #| Format-Table | Out-String | Write-Host
            $tempTriggers += ($scheduleItem | Select-Object branchFilters, @{name="triggerType";expression= {"schedule"}}, @{name="schedule"; expression= { 
                [string] $tempHour = $_.startHours
                $tempHour = $tempHour.PadLeft(2,'0')
                [string] $tempMinute = $_.startMinutes
                $tempMinute = $tempMinute.PadLeft(2,'0')
                "$($tempHour):$($tempMinute)"
            }})

            $triggers += $tempTriggers | Select-Object @{name = "organization"; expression = {$organization.accountName}}, @{name = "project"; expression={$project.name}}, @{name="pipeline";expression={$pipeline.name}}, *            
        }                
    }        
}

$sortOrder = "schedule", "continuousIntegration", "yaml", "none"
# $triggers | Where-Object {$_.TriggerType -eq "yaml"} | Sort-Object -Property project, pipeline | Format-Table | Out-String | Write-Host
$triggers | Sort-Object organization, project, {$sortOrder.IndexOf($_.TriggerType)} | Format-Table | Out-String | Write-Host