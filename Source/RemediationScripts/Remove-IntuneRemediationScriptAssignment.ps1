# Write the comment-based HELP for Remove-IntuneRemediationScriptAssignment
<#
.SYNOPSIS
    Removes an Intune remediation script assignment.

.DESCRIPTION
    Removes an Intune remediation script assignment.

.PARAMETER Id
    The id of the remediation script to remove assignment from.

.PARAMETER Name
    The name of the remediation script to remove assignment from.

.PARAMETER GroupId
    The id of the group to remove the remediation script assignment from.

.PARAMETER Environment
    The environment to connect to. Valid values are Global, USGov, USGovDoD. Default is Global.

.EXAMPLE
    # Remove a remediation script assignment by ID.
    Remove-IntuneRemediationScriptAssignment -Id "00000000-0000-0000-0000-000000000000" -GroupId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Remove a remediation script assignment by name.
    Remove-IntuneRemediationScriptAssignment -Name "Set Extension Attribute" -GroupId "00000000-0000-0000-0000-000000000000"

.NOTES
    Required Graph scopes:
      - DeviceManagementScripts.ReadWrite.All
#>

function Remove-IntuneRemediationScriptAssignment
{
    param (     
        [Parameter(Mandatory, ParameterSetName="ById", Position=0, HelpMessage="Remediation Script Id")]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$Id,   
        [Parameter(Mandatory, ParameterSetName="ByName", Position=0)]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName="ById", Position=1)]
        [Parameter(Mandatory, ParameterSetName="ByName", Position=1)]
        [ValidateScript({$GUIDRegex = "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$";If ($_ -match $GUIDRegex){return $true}throw "'$_': This is not a valid GUID format"})]
        [string]$GroupId,
        [Parameter(ParameterSetName="ById")]
        [Parameter(ParameterSetName="ByName")]
        [ValidateSet("Global", "USGov", "USGovDoD")]
        [string]$Environment="Global"
    )
    begin 
    {
        if($false -eq (Initialize-IntuneAccess -Scopes @("DeviceManagementScripts.ReadWrite.All") -Modules @("Microsoft.Graph.Authentication") -Environment $Environment))
        {
            return
        }
        
        if($PSBoundParameters.ContainsKey("GroupId"))
        {
            $groupId = $GroupId
        }
        else 
        {
            $groupId = $Id
        }

        switch ($Environment) {
            "USGov" { $uri = "https://graph.microsoft.us" }
            "USGovDoD" { $uri = "https://dod-graph.microsoft.us" }
            Default { $uri = "https://graph.microsoft.com" }
        }
        $graphVersion = "beta"
    }
    process
    {
        # If Name is provided, resolve to ID first
        if ($PSCmdlet.ParameterSetName -eq "ByName") {
            try {
                $script = Get-IntuneRemediationScript -Name $Name -Environment $Environment
                if (-not $script) {
                    Write-Error "No remediation script found with name: $Name"
                    return
                }
                if ($script.Count -gt 1) {
                    Write-Error "Multiple scripts found with name '$Name'. Use -Id parameter with specific script ID instead."
                    return
                }
                $Id = $script.id
                Write-Verbose "Resolved '$Name' to ID: $Id"
            } catch {
                Write-Error "Failed to resolve script name '$Name': $($_.Exception.Message)"
                return
            }
        }

        # Get raw assignments directly from API (not the user-friendly format)
        $response = Invoke-MgRestMethod -Method Get -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts('$Id')/assignments" -OutputType Json | ConvertFrom-Json
        $assignments = @()
        foreach($assignment in $response.value) {
            if([string]::IsNullOrEmpty($assignment.target.deviceAndAppManagementAssignmentFilterId)) {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        groupId = $assignment.target.groupId
                    }
                    runRemediationScript = $assignment.runRemediationScript
                    runSchedule = $assignment.runSchedule
                }
            } else {
                $newAssignment = [PSCustomObject]@{
                    id = $assignment.id
                    target = [PSCustomObject]@{
                        "@odata.type" = $assignment.target.'@odata.type'
                        deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        groupId = $assignment.target.groupId
                    }
                    runRemediationScript = $assignment.runRemediationScript
                    runSchedule = $assignment.runSchedule
                }
            }
            $assignments += $newAssignment
        }
        $Assignments = $assignments
        $updatedAssignmentArray = @()

        ForEach($assignment in $Assignments){

            If ($Assignment.target.groupId -ne $groupID){

                If ([string]::IsNullOrEmpty($Assignment.target.deviceAndAppManagementAssignmentFilterType) -eq $FALSE){

                    $targetGroup = [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            "@odata.type" = $Assignment.target.'@odata.type'
                            deviceAndAppManagementAssignmentFilterId = $Assignment.target.deviceAndAppManagementAssignmentFilterId
                            deviceAndAppManagementAssignmentFilterType = $Assignment.target.deviceAndAppManagementAssignmentFilterType
                            groupId = $Assignment.target.groupId
                        }
                        runRemediationScript = if($Assignment.runRemediationScript -ne $null) { $Assignment.runRemediationScript } else { $true }
                        runSchedule = $Assignment.runSchedule
                    }  

                }Else{

                    $targetGroup = [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            "@odata.type" = $Assignment.target.'@odata.type'
                            groupId = $Assignment.target.groupId
                        }
                        runRemediationScript = if($Assignment.runRemediationScript -ne $null) { $Assignment.runRemediationScript } else { $true }
                        runSchedule = $Assignment.runSchedule
                    }

                }
                
                $updatedAssignmentArray += $TargetGroup   

            }
        
        }

        $body = @{
            deviceHealthScriptAssignments = $updatedAssignmentArray
        }

        Write-Verbose "Request body: $(ConvertTo-Json $body -Depth 10)"
        $response = Invoke-MgRestMethod -Method POST -Uri "$uri/$graphVersion/deviceManagement/deviceHealthScripts('$Id')/assign" -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -OutputType Json | ConvertFrom-Json
        return $response

    }

}
