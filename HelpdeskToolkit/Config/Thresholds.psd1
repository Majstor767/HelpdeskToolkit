@{
    # All limits that decide between OK / Warning / Critical live in this file.
    # Change a number here and every check picks it up on the next module import.
    #
    # "Typical" values are rules of thumb for a healthy office PC. They are printed
    # next to the measured value for comparison only and never affect the status.

    Uptime        = @{
        # More days than this since the last boot = Warning.
        WarningDays = 7
        Typical     = '0 - 3 days'
    }

    WindowsSupport = @{
        # Last day on which Microsoft releases security updates for a Windows version.
        # Source: the Windows lifecycle pages on learn.microsoft.com/lifecycle, read on
        # 2026-10-01. Add a line when Microsoft publishes a new feature release.
        Windows10End         = '2025-10-14'
        # Home, Pro, Pro Education and Pro for Workstations
        HomePro              = @{
            '21H2' = '2023-10-10'
            '22H2' = '2024-10-08'
            '23H2' = '2025-11-11'
            '24H2' = '2026-10-13'
            '25H2' = '2027-10-12'
            '26H1' = '2028-03-14'
            '26H2' = '2028-10-09'
        }
        # Enterprise and Education
        Enterprise           = @{
            '21H2' = '2024-10-08'
            '22H2' = '2025-10-14'
            '23H2' = '2026-11-10'
            '24H2' = '2027-10-12'
            '25H2' = '2028-10-10'
            '26H1' = '2029-03-13'
            '26H2' = '2029-10-08'
        }
        # Fewer days than this until the end of support = Warning.
        WarningDaysBeforeEnd = 90
    }

    Stability     = @{
        # Stability index of Reliability Monitor (1 = unstable, 10 = stable) below these values.
        WarningIndex  = 5
        CriticalIndex = 3
        Typical       = '8 - 10'
    }

    Startup       = @{
        # More programs than this starting with Windows = Warning.
        WarningProgramCount = 15
        Typical             = '5 - 10'
    }

    Cpu           = @{
        # CPU load above these percentages.
        WarningPercent  = 85
        CriticalPercent = 95
        Typical         = '5 - 30 % when idle'
    }

    Memory        = @{
        # Used RAM above these percentages.
        WarningPercent  = 85
        CriticalPercent = 95
        Typical         = '40 - 70 %'
    }

    Disk          = @{
        # Free space below these percentages of the disk size.
        WarningFreePercent  = 15
        CriticalFreePercent = 5
        Typical             = '25 % free or more'
    }

    Cleanup       = @{
        # Space that could be freed: more gigabytes than this = Warning.
        TempWarningGb       = 5
        RecycleBinWarningGb = 10
        # Counting stops after this many milliseconds per folder, so a huge folder
        # cannot hold up the whole check; the size is then reported as "or more".
        TimeoutMs           = 3000
    }

    PageFile      = @{
        # Page file usage above this percentage = Warning.
        WarningPercent = 80
        Typical        = '0 - 30 %'
    }

    Battery       = @{
        # Charge below these percentages while running on battery.
        WarningPercent  = 20
        CriticalPercent = 10
    }

    EventLog      = @{
        # Number of events per log in the selected period (-Days).
        # More than this many = Warning / Critical.
        CriticalEventWarningAbove      = 0
        CriticalEventCriticalAbove     = 4
        TypicalCriticalEvents          = '0'
        ErrorEventWarningAbove         = 50
        TypicalErrorEvents             = '0 - 20 per week'
        # Unexpected shutdowns (power loss, crash, forced power-off).
        UnexpectedShutdownWarningAbove = 0
        TypicalUnexpectedShutdowns     = '0'
        # Blue screens (Windows crashes).
        BlueScreenWarningAbove         = 0
        TypicalBlueScreens             = '0'
    }

    Software      = @{
        # Programs installed within this many days are listed as "recently installed".
        RecentDays        = 30
        # More application crashes than this in the selected period (-Days) = Warning.
        CrashWarningAbove = 5
        TypicalCrashes    = '0 - 2 per week'
    }

    WindowsUpdate = @{
        # More days than this since the last installed update = Warning.
        WarningDaysSinceLastUpdate = 45
        # Windows quality updates are released once a month.
        Typical                    = '0 - 30 days'
    }

    Defender      = @{
        # Antivirus definitions older than this many days.
        SignatureWarningDays  = 3
        SignatureCriticalDays = 7
        # Definitions are normally updated every day.
        Typical               = '0 - 1 days'
        # More days than this since the last quick scan = Warning.
        ScanWarningDays       = 14
        # Defender runs a quick scan on its own about once a week.
        TypicalScan           = '0 - 7 days'
    }

    Printers      = @{
        # A document waiting in the print queue longer than this many minutes counts as stuck.
        StuckJobMinutes = 10
    }

    Network       = @{
        # Targets of the connectivity tests.
        PingTarget          = '1.1.1.1'
        DnsTestName         = 'microsoft.com'
        HttpsTestUrl        = 'https://www.microsoft.com'
        # Average ping to the internet above this many milliseconds = Warning.
        PingWarningMs       = 150
        TypicalGatewayPing  = 'under 5 ms'
        TypicalInternetPing = '10 - 50 ms'
        # Clock differing from internet time by more than this many seconds = Warning.
        # Sign-in in a domain fails when the difference exceeds 5 minutes.
        ClockWarningSeconds = 120
        TypicalClock        = '0 - 5 seconds'
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
