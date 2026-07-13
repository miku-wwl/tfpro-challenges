param(
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [Parameter(Mandatory = $true)][string]$ProducerState,
    [Parameter(Mandatory = $true)][string]$ConsumerState
)

$ErrorActionPreference = "Stop"

# TODO: deploy producer and then consumer. For each root:
# - init with the supplied local backend path and -input=false
# - create a saved plan with -out and -input=false
# - apply exactly that saved plan with -input=false
# The consumer plan also needs producer_state_path.
throw "TODO: implement ordered, saved-plan deployment"
