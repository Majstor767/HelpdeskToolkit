@{
    # Programs whose maker no longer releases security updates for them.
    #
    # Match  regular expression for the name of the program as "Installed apps" shows
    #        it (the version is part of many names: "Python 3.8.10 (64-bit)")
    # End    the last day with security updates; an entry counts from the day after
    # Level  'Warning' for programs that open files from the internet or are reachable
    #        from the network, 'Info' for runtimes that other programs bring along and
    #        that the user cannot simply remove
    #
    # Sources: the lifecycle pages of the makers (learn.microsoft.com/lifecycle,
    # helpx.adobe.com, devguide.python.org/versions, oracle.com/java), read on 2026-10-02.
    # Add a line when a maker ends the support of another version.
    #
    # Left out on purpose: the Visual C++ runtimes of 2005 - 2013. Almost every
    # computer has them because old programs install them, and removing them breaks
    # those programs.
    Products = @(
        # --- Adobe ------------------------------------------------------------------
        @{ Match = '^Adobe Flash Player'; End = '2020-12-31'; Level = 'Warning' }
        @{ Match = '^Adobe Shockwave Player'; End = '2019-04-09'; Level = 'Warning' }
        @{ Match = '^Adobe (Acrobat )?Reader (9|X|XI)\b'; End = '2017-10-15'; Level = 'Warning' }
        @{ Match = '^Adobe Acrobat (Reader )?2017\b'; End = '2022-06-06'; Level = 'Warning' }
        @{ Match = '^Adobe Acrobat (Reader )?2020\b'; End = '2025-11-30'; Level = 'Warning' }

        # --- Microsoft Office and communication ------------------------------------
        @{ Match = '^Microsoft Office .*\b2007\b'; End = '2017-10-10'; Level = 'Warning' }
        @{ Match = '^Microsoft Office .*\b2010\b'; End = '2020-10-13'; Level = 'Warning' }
        @{ Match = '^Microsoft Office .*\b2013\b'; End = '2023-04-11'; Level = 'Warning' }
        @{ Match = '^Microsoft Office .*\b2016\b'; End = '2025-10-14'; Level = 'Warning' }
        @{ Match = '^Microsoft Office .*\b2019\b'; End = '2025-10-14'; Level = 'Warning' }
        @{ Match = '^Skype( version| for Desktop)?\b(?! for Business)'; End = '2025-05-05'; Level = 'Warning' }
        @{ Match = '^Microsoft Teams classic'; End = '2025-07-01'; Level = 'Warning' }
        @{ Match = '^Microsoft Silverlight'; End = '2021-10-12'; Level = 'Warning' }
        @{ Match = '^Windows (Live )?Essentials'; End = '2017-01-10'; Level = 'Warning' }

        # --- Other programs that open content from the internet --------------------
        @{ Match = '^QuickTime'; End = '2016-04-14'; Level = 'Warning' }
        @{ Match = '^Java(\(TM\))? [67] Update'; End = '2022-07-31'; Level = 'Warning' }

        # --- Database servers -------------------------------------------------------
        @{ Match = '^Microsoft SQL Server 2008( R2)?( \(64-bit\))?$'; End = '2019-07-09'; Level = 'Warning' }
        @{ Match = '^Microsoft SQL Server 2012( \(64-bit\))?$'; End = '2022-07-12'; Level = 'Warning' }
        @{ Match = '^Microsoft SQL Server 2014( \(64-bit\))?$'; End = '2024-07-09'; Level = 'Warning' }
        @{ Match = '^Microsoft SQL Server 2016( \(64-bit\))?$'; End = '2026-07-14'; Level = 'Warning' }

        # --- Runtimes ---------------------------------------------------------------
        @{ Match = '^Python 2\.'; End = '2020-01-01'; Level = 'Info' }
        @{ Match = '^Python 3\.[0-7]\.'; End = '2023-06-27'; Level = 'Info' }
        @{ Match = '^Python 3\.8\.'; End = '2024-10-07'; Level = 'Info' }
        @{ Match = '^Python 3\.9\.'; End = '2025-10-31'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET Core|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b[23]\.[01]\.\d'; End = '2022-12-13'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b5\.0\.\d'; End = '2022-05-10'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b6\.0\.\d'; End = '2024-11-12'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b7\.0\.\d'; End = '2024-05-14'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b8\.0\.\d'; End = '2026-11-10'; Level = 'Info' }
        @{ Match = '^Microsoft (\.NET|ASP\.NET Core|Windows Desktop) (Runtime|SDK)?.*\b9\.0\.\d'; End = '2026-11-10'; Level = 'Info' }
    )
}
