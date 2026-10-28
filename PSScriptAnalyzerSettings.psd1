@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The scripts are interactive CLI steps that talk to a person, not pipeline commands
        'PSAvoidUsingWriteHost',
        # Steps take -DryRun (print instead of run) rather than -WhatIf/-Confirm
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
