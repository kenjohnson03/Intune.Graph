function New-GraphBatchRequest
{
    param (        
        [Parameter(Mandatory, Position=0)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE", "PUT")]
        [string]$Method,
        [Parameter(Mandatory, Position=1)]
        [string]$Uri,
        [Parameter(Position=2)]
        [hashtable]$Body,
        [Parameter(Position=3)]
        [string]$Id=1,
        [Parameter(Position=4)]
        [hashtable]$Headers,
        [Parameter(Position=5)]
        [string[]]$DependsOn
    )
    process {
        $batch = @{}
        $batch.id = $Id
        $batch.method = $Method
        $batch.url = $Uri        
        $batch.body = $Body
        if($null -ne $Headers)
        {
            $batch.headers = $Headers
        }
        if($null -ne $DependsOn)
        {
            $batch.dependsOn = $DependsOn
        }
        
        return $batch        
    }
}
