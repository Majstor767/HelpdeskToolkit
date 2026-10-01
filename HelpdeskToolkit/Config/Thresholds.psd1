@{
    # All limits that decide between OK / Warning / Critical live in this file.
    # Change a number here and every check picks it up on the next module import.

    Uptime        = @{
        # More days than this since the last boot = Warning.
        WarningDays = 7
    }

    Cpu           = @{
        # CPU load above these percentages.
        WarningPercent  = 85
        CriticalPercent = 95
    }

    Memory        = @{
        # Used RAM above these percentages.
        WarningPercent  = 85
        CriticalPercent = 95
    }

    Disk          = @{
        # Free space below these percentages of the disk size.
        WarningFreePercent  = 15
        CriticalFreePercent = 5
    }

    Battery       = @{
        # Charge below these percentages while running on battery.
        WarningPercent  = 20
        CriticalPercent = 10
    }

    EventLog      = @{
        # Number of events per log in the selected period (-Days).
        # More than this many = Warning / Critical.
        CriticalEventWarningAbove  = 0
        CriticalEventCriticalAbove = 4
        ErrorEventWarningAbove     = 50
    }

    WindowsUpdate = @{
        # More days than this since the last installed update = Warning.
        WarningDaysSinceLastUpdate = 45
    }

    Defender      = @{
        # Antivirus definitions older than this many days.
        SignatureWarningDays  = 3
        SignatureCriticalDays = 7
    }

    Network       = @{
        # Targets of the connectivity tests.
        PingTarget    = '1.1.1.1'
        DnsTestName   = 'microsoft.com'
        HttpsTestUrl  = 'https://www.microsoft.com'
        # Average ping to the internet above this many milliseconds = Warning.
        PingWarningMs = 150
    }

    # Services (by service name) whose state is reported in the Services category.
    Services      = @(
        'Dhcp'
        'Dnscache'
        'EventLog'
        'LanmanWorkstation'
        'mpssvc'
        'WinDefend'
        'wuauserv'
        'BITS'
        'Spooler'
    )
}
