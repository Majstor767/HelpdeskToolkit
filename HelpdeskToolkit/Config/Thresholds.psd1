@{
    # All limits that decide between OK / Warning / Critical live in this file.
    # Change a number here and every check picks it up on the next module import.

    Uptime = @{
        # Days since last boot before a restart is recommended.
        WarningDays = 7
    }
}
