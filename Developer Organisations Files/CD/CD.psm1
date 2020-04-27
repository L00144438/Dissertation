# This is a simple example of the Continuous Delivery Server script
# This script would identify if the connecting customer is has the correct app version
# This script to be saved in C:\pwsh\Modules\CD so it is available
function Check-Release {
    param (
        [Parameter (position=0)][string] $OperationsID,
        [Parameter (position=1)][string] $AppVersion       
    )
    if ($AppVersion -eq "10.0.17763.475") {return ""}
    Else {return ("C:\drop")}           
}

