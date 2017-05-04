// Written in the D programming language

/++
    License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis
    Source:    $(PHOBOSSRC std/_datetime.d)
    Macros:
        LREF2=<a href="#$1">$(D $2)</a>
+/
module std.datetime.timezone;

import core.time : Duration, dur;
import std.datetime.common;
import std.exception : enforce;

version(Windows)
{
    import core.stdc.time : time_t;
    import core.sys.windows.windows;
    import core.sys.windows.winsock2;
    import std.windows.registry;

    // Uncomment and run unittests to print missing Windows TZ translations.
    // Please subscribe to Microsoft Daylight Saving Time & Time Zone Blog
    // (https://blogs.technet.microsoft.com/dst2007/) if you feel responsible
    // for updating the translations.
    // version = UpdateWindowsTZTranslations;
}
else version(Posix)
{
    import core.sys.posix.signal : timespec;
    import core.sys.posix.sys.types : time_t;
}

version(unittest) import std.exception : assertThrown;

import std.datetime : clearTZEnvVar, Date, DateTime, PosixTimeZone, setTZEnvVar, SysTime, TimeOfDay, UTC; // temporary

/++
    Represents a time zone. It is used with $(LREF SysTime) to indicate the time
    zone of a $(LREF SysTime).
  +/
abstract class TimeZone
{
public:

    /++
        The name of the time zone per the TZ Database. This is the name used to
        get a $(LREF2 .TimeZone, TimeZone) by name with $(D TimeZone.getTimeZone).

        See_Also:
            $(HTTP en.wikipedia.org/wiki/Tz_database, Wikipedia entry on TZ
              Database)<br>
            $(HTTP en.wikipedia.org/wiki/List_of_tz_database_time_zones, List of
              Time Zones)
      +/
    @property string name() @safe const nothrow
    {
        return _name;
    }


    /++
        Typically, the abbreviation (generally 3 or 4 letters) for the time zone
        when DST is $(I not) in effect (e.g. PST). It is not necessarily unique.

        However, on Windows, it may be the unabbreviated name (e.g. Pacific
        Standard Time). Regardless, it is not the same as name.
      +/
    @property string stdName() @safe const nothrow
    {
        return _stdName;
    }


    /++
        Typically, the abbreviation (generally 3 or 4 letters) for the time zone
        when DST $(I is) in effect (e.g. PDT). It is not necessarily unique.

        However, on Windows, it may be the unabbreviated name (e.g. Pacific
        Daylight Time). Regardless, it is not the same as name.
      +/
    @property string dstName() @safe const nothrow
    {
        return _dstName;
    }


    /++
        Whether this time zone has Daylight Savings Time at any point in time.
        Note that for some time zone types it may not have DST for current dates
        but will still return true for $(D hasDST) because the time zone did at
        some point have DST.
      +/
    @property abstract bool hasDST() @safe const nothrow;


    /++
        Takes the number of hnsecs (100 ns) since midnight, January 1st, 1 A.D.
        in UTC time (i.e. std time) and returns whether DST is effect in this
        time zone at the given point in time.

        Params:
            stdTime = The UTC time that needs to be checked for DST in this time
                      zone.
      +/
    abstract bool dstInEffect(long stdTime) @safe const nothrow;


    /++
        Takes the number of hnsecs (100 ns) since midnight, January 1st, 1 A.D.
        in UTC time (i.e. std time) and converts it to this time zone's time.

        Params:
            stdTime = The UTC time that needs to be adjusted to this time zone's
                      time.
      +/
    abstract long utcToTZ(long stdTime) @safe const nothrow;


    /++
        Takes the number of hnsecs (100 ns) since midnight, January 1st, 1 A.D.
        in this time zone's time and converts it to UTC (i.e. std time).

        Params:
            adjTime = The time in this time zone that needs to be adjusted to
                      UTC time.
      +/
    abstract long tzToUTC(long adjTime) @safe const nothrow;


    /++
        Returns what the offset from UTC is at the given std time.
        It includes the DST offset in effect at that time (if any).

        Params:
            stdTime = The UTC time for which to get the offset from UTC for this
                      time zone.
      +/
    Duration utcOffsetAt(long stdTime) @safe const nothrow
    {
        return dur!"hnsecs"(utcToTZ(stdTime) - stdTime);
    }

    // @@@DEPRECATED_2017-07@@@
    /++
        $(RED Deprecated. Use either PosixTimeZone.getTimeZone or
              WindowsTimeZone.getTimeZone. ($(LREF parseTZConversions) can be
              used to convert time zone names if necessary). Microsoft changes
              their time zones too often for us to compile the conversions into
              Phobos and have them be properly up-to-date. TimeZone.getTimeZone
              will be removed in July 2017.)

        Returns a $(LREF2 .TimeZone, TimeZone) with the give name per the TZ Database.

        This returns a $(LREF PosixTimeZone) on Posix systems and a
        $(LREF WindowsTimeZone) on Windows systems. For
        $(LREF PosixTimeZone) on Windows, call $(D PosixTimeZone.getTimeZone)
        directly and give it the location of the TZ Database time zone files on
        disk.

        On Windows, the given TZ Database name is converted to the corresponding
        time zone name on Windows prior to calling
        $(D WindowsTimeZone.getTimeZone). This function allows for
        the same time zone names on both Windows and Posix systems.

        See_Also:
            $(HTTP en.wikipedia.org/wiki/Tz_database, Wikipedia entry on TZ
              Database)<br>
            $(HTTP en.wikipedia.org/wiki/List_of_tz_database_time_zones, List of
              Time Zones)<br>
            $(HTTP unicode.org/repos/cldr-tmp/trunk/diff/supplemental/zone_tzid.html,
                  Windows <-> TZ Database Name Conversion Table)

        Params:
            name = The TZ Database name of the desired time zone

        Throws:
            $(LREF DateTimeException) if the given time zone could not be found.
      +/
    deprecated("Use PosixTimeZone.getTimeZone or WindowsTimeZone.getTimeZone instead")
    static immutable(TimeZone) getTimeZone(string name) @safe
    {
        version(Posix)
            return PosixTimeZone.getTimeZone(name);
        else version(Windows)
        {
            import std.format : format;
            auto windowsTZName = tzDatabaseNameToWindowsTZName(name);
            if (windowsTZName != null)
            {
                try
                    return WindowsTimeZone.getTimeZone(windowsTZName);
                catch (DateTimeException dte)
                {
                    auto oldName = _getOldName(windowsTZName);
                    if (oldName != null)
                        return WindowsTimeZone.getTimeZone(oldName);
                    throw dte;
                }
            }
            else
                throw new DateTimeException(format("%s does not have an equivalent Windows time zone.", name));
        }
    }

    ///
    deprecated @safe unittest
    {
        auto tz = TimeZone.getTimeZone("America/Los_Angeles");
    }

    // The purpose of this is to handle the case where a Windows time zone is
    // new and exists on an up-to-date Windows box but does not exist on Windows
    // boxes which have not been properly updated. The "date added" is included
    // on the theory that we'll be able to remove them at some point in the
    // the future once enough time has passed, and that way, we know how much
    // time has passed.
    private static string _getOldName(string windowsTZName) @safe pure nothrow
    {
        switch (windowsTZName)
        {
            case "Belarus Standard Time": return "Kaliningrad Standard Time"; // Added 2014-10-08
            case "Russia Time Zone 10": return "Magadan Standard Time"; // Added 2014-10-08
            case "Russia Time Zone 11": return "Magadan Standard Time"; // Added 2014-10-08
            case "Russia Time Zone 3": return "Russian Standard Time"; // Added 2014-10-08
            default: return null;
        }
    }

    // Since reading in the time zone files could be expensive, most unit tests
    // are consolidated into this one unittest block which minimizes how often
    // it reads a time zone file.
    @system unittest
    {
        import core.exception : AssertError;
        import std.conv : to;
        import std.file : exists, isFile;
        import std.format : format;
        import std.path : chainPath;
        import std.stdio : writefln;
        import std.typecons : tuple;

        version(Posix) alias getTimeZone = PosixTimeZone.getTimeZone;
        else version(Windows) alias getTimeZone = WindowsTimeZone.getTimeZone;

        version(Posix) scope(exit) clearTZEnvVar();

        static immutable(TimeZone) testTZ(string tzName,
                                          string stdName,
                                          string dstName,
                                          Duration utcOffset,
                                          Duration dstOffset,
                                          bool north = true)
        {
            scope(failure) writefln("Failed time zone: %s", tzName);

            version(Posix)
            {
                immutable tz = PosixTimeZone.getTimeZone(tzName);
                assert(tz.name == tzName);
            }
            else version(Windows)
            {
                immutable tz = WindowsTimeZone.getTimeZone(tzName);
                assert(tz.name == stdName);
            }

            immutable hasDST = dstOffset != Duration.zero;

            //assert(tz.stdName == stdName);  //Locale-dependent
            //assert(tz.dstName == dstName);  //Locale-dependent
            assert(tz.hasDST == hasDST);

            immutable stdDate = DateTime(2010, north ? 1 : 7, 1, 6, 0, 0);
            immutable dstDate = DateTime(2010, north ? 7 : 1, 1, 6, 0, 0);
            auto std = SysTime(stdDate, tz);
            auto dst = SysTime(dstDate, tz);
            auto stdUTC = SysTime(stdDate - utcOffset, UTC());
            auto dstUTC = SysTime(stdDate - utcOffset + dstOffset, UTC());

            assert(!std.dstInEffect);
            assert(dst.dstInEffect == hasDST);
            assert(tz.utcOffsetAt(std.stdTime) == utcOffset);
            assert(tz.utcOffsetAt(dst.stdTime) == utcOffset + dstOffset);

            assert(cast(DateTime) std == stdDate);
            assert(cast(DateTime) dst == dstDate);
            assert(std == stdUTC);

            version(Posix)
            {
                setTZEnvVar(tzName);

                static void testTM(in SysTime st)
                {
                    import core.stdc.time : localtime, tm;
                    time_t unixTime = st.toUnixTime();
                    tm* osTimeInfo = localtime(&unixTime);
                    tm ourTimeInfo = st.toTM();

                    assert(ourTimeInfo.tm_sec == osTimeInfo.tm_sec);
                    assert(ourTimeInfo.tm_min == osTimeInfo.tm_min);
                    assert(ourTimeInfo.tm_hour == osTimeInfo.tm_hour);
                    assert(ourTimeInfo.tm_mday == osTimeInfo.tm_mday);
                    assert(ourTimeInfo.tm_mon == osTimeInfo.tm_mon);
                    assert(ourTimeInfo.tm_year == osTimeInfo.tm_year);
                    assert(ourTimeInfo.tm_wday == osTimeInfo.tm_wday);
                    assert(ourTimeInfo.tm_yday == osTimeInfo.tm_yday);
                    assert(ourTimeInfo.tm_isdst == osTimeInfo.tm_isdst);
                    assert(ourTimeInfo.tm_gmtoff == osTimeInfo.tm_gmtoff);
                    assert(to!string(ourTimeInfo.tm_zone) == to!string(osTimeInfo.tm_zone));
                }

                testTM(std);
                testTM(dst);

                // Apparently, right/ does not exist on Mac OS X. I don't know
                // whether or not it exists on FreeBSD. It's rather pointless
                // normally, since the Posix standard requires that leap seconds
                // be ignored, so it does make some sense that right/ wouldn't
                // be there, but since PosixTimeZone _does_ use leap seconds if
                // the time zone file does, we'll test that functionality if the
                // appropriate files exist.
                if (chainPath(PosixTimeZone.defaultTZDatabaseDir, "right", tzName).exists)
                {
                    auto leapTZ = PosixTimeZone.getTimeZone("right/" ~ tzName);

                    assert(leapTZ.name == "right/" ~ tzName);
                    //assert(leapTZ.stdName == stdName);  //Locale-dependent
                    //assert(leapTZ.dstName == dstName);  //Locale-dependent
                    assert(leapTZ.hasDST == hasDST);

                    auto leapSTD = SysTime(std.stdTime, leapTZ);
                    auto leapDST = SysTime(dst.stdTime, leapTZ);

                    assert(!leapSTD.dstInEffect);
                    assert(leapDST.dstInEffect == hasDST);

                    assert(leapSTD.stdTime == std.stdTime);
                    assert(leapDST.stdTime == dst.stdTime);

                    // Whenever a leap second is added/removed,
                    // this will have to be adjusted.
                    //enum leapDiff = convert!("seconds", "hnsecs")(25);
                    //assert(leapSTD.adjTime - leapDiff == std.adjTime);
                    //assert(leapDST.adjTime - leapDiff == dst.adjTime);
                }
            }

            return tz;
        }

        auto dstSwitches = [/+America/Los_Angeles+/ tuple(DateTime(2012, 3, 11),  DateTime(2012, 11, 4), 2, 2),
                            /+America/New_York+/    tuple(DateTime(2012, 3, 11),  DateTime(2012, 11, 4), 2, 2),
                            ///+America/Santiago+/    tuple(DateTime(2011, 8, 21),  DateTime(2011, 5, 8), 0, 0),
                            /+Europe/London+/       tuple(DateTime(2012, 3, 25),  DateTime(2012, 10, 28), 1, 2),
                            /+Europe/Paris+/        tuple(DateTime(2012, 3, 25),  DateTime(2012, 10, 28), 2, 3),
                            /+Australia/Adelaide+/  tuple(DateTime(2012, 10, 7),  DateTime(2012, 4, 1), 2, 3)];

        version(Posix)
        {
            version(FreeBSD)      enum utcZone = "Etc/UTC";
            else version(NetBSD)  enum utcZone = "UTC";
            else version(linux)   enum utcZone = "UTC";
            else version(OSX)     enum utcZone = "UTC";
            else static assert(0, "The location of the UTC timezone file on this Posix platform must be set.");

            auto tzs = [testTZ("America/Los_Angeles", "PST", "PDT", dur!"hours"(-8), dur!"hours"(1)),
                        testTZ("America/New_York", "EST", "EDT", dur!"hours"(-5), dur!"hours"(1)),
                        //testTZ("America/Santiago", "CLT", "CLST", dur!"hours"(-4), dur!"hours"(1), false),
                        testTZ("Europe/London", "GMT", "BST", dur!"hours"(0), dur!"hours"(1)),
                        testTZ("Europe/Paris", "CET", "CEST", dur!"hours"(1), dur!"hours"(1)),
                        // Per www.timeanddate.com, it should be "CST" and "CDT",
                        // but the OS insists that it's "CST" for both. We should
                        // probably figure out how to report an error in the TZ
                        // database and report it.
                        testTZ("Australia/Adelaide", "CST", "CST",
                               dur!"hours"(9) + dur!"minutes"(30), dur!"hours"(1), false)];

            testTZ(utcZone, "UTC", "UTC", dur!"hours"(0), dur!"hours"(0));
            assertThrown!DateTimeException(PosixTimeZone.getTimeZone("hello_world"));
        }
        else version(Windows)
        {
            auto tzs = [testTZ("Pacific Standard Time", "Pacific Standard Time",
                               "Pacific Daylight Time", dur!"hours"(-8), dur!"hours"(1)),
                        testTZ("Eastern Standard Time", "Eastern Standard Time",
                               "Eastern Daylight Time", dur!"hours"(-5), dur!"hours"(1)),
                        //testTZ("Pacific SA Standard Time", "Pacific SA Standard Time",
                               //"Pacific SA Daylight Time", dur!"hours"(-4), dur!"hours"(1), false),
                        testTZ("GMT Standard Time", "GMT Standard Time",
                               "GMT Daylight Time", dur!"hours"(0), dur!"hours"(1)),
                        testTZ("Romance Standard Time", "Romance Standard Time",
                               "Romance Daylight Time", dur!"hours"(1), dur!"hours"(1)),
                        testTZ("Cen. Australia Standard Time", "Cen. Australia Standard Time",
                               "Cen. Australia Daylight Time",
                               dur!"hours"(9) + dur!"minutes"(30), dur!"hours"(1), false)];

            testTZ("Greenwich Standard Time", "Greenwich Standard Time",
                   "Greenwich Daylight Time", dur!"hours"(0), dur!"hours"(0));
            assertThrown!DateTimeException(WindowsTimeZone.getTimeZone("hello_world"));
        }
        else
            assert(0, "OS not supported.");

        foreach (i; 0 .. tzs.length)
        {
            auto tz = tzs[i];
            immutable spring = dstSwitches[i][2];
            immutable fall = dstSwitches[i][3];
            auto stdOffset = SysTime(dstSwitches[i][0] + dur!"days"(-1), tz).utcOffset;
            auto dstOffset = stdOffset + dur!"hours"(1);

            // Verify that creating a SysTime in the given time zone results
            // in a SysTime with the correct std time during and surrounding
            // a DST switch.
            foreach (hour; -12 .. 13)
            {
                auto st = SysTime(dstSwitches[i][0] + dur!"hours"(hour), tz);
                immutable targetHour = hour < 0 ? hour + 24 : hour;

                static void testHour(SysTime st, int hour, string tzName, size_t line = __LINE__)
                {
                    enforce(st.hour == hour,
                            new AssertError(format("[%s] [%s]: [%s] [%s]", st, tzName, st.hour, hour),
                                            __FILE__, line));
                }

                void testOffset1(Duration offset, bool dstInEffect, size_t line = __LINE__)
                {
                    AssertError msg(string tag)
                    {
                        return new AssertError(format("%s [%s] [%s]: [%s] [%s] [%s]",
                                                      tag, st, tz.name, st.utcOffset, stdOffset, dstOffset),
                                               __FILE__, line);
                    }

                    enforce(st.dstInEffect == dstInEffect, msg("1"));
                    enforce(st.utcOffset == offset, msg("2"));
                    enforce((st + dur!"minutes"(1)).utcOffset == offset, msg("3"));
                }

                if (hour == spring)
                {
                    testHour(st, spring + 1, tz.name);
                    testHour(st + dur!"minutes"(1), spring + 1, tz.name);
                }
                else
                {
                    testHour(st, targetHour, tz.name);
                    testHour(st + dur!"minutes"(1), targetHour, tz.name);
                }

                if (hour < spring)
                    testOffset1(stdOffset, false);
                else
                    testOffset1(dstOffset, true);

                st = SysTime(dstSwitches[i][1] + dur!"hours"(hour), tz);
                testHour(st, targetHour, tz.name);

                // Verify that 01:00 is the first 01:00 (or whatever hour before the switch is).
                if (hour == fall - 1)
                    testHour(st + dur!"hours"(1), targetHour, tz.name);

                if (hour < fall)
                    testOffset1(dstOffset, true);
                else
                    testOffset1(stdOffset, false);
            }

            // Verify that converting a time in UTC to a time in another
            // time zone results in the correct time during and surrounding
            // a DST switch.
            bool first = true;
            auto springSwitch = SysTime(dstSwitches[i][0] + dur!"hours"(spring), UTC()) - stdOffset;
            auto fallSwitch = SysTime(dstSwitches[i][1] + dur!"hours"(fall), UTC()) - dstOffset;
            // @@@BUG@@@ 3659 makes this necessary.
            auto fallSwitchMinus1 = fallSwitch - dur!"hours"(1);

            foreach (hour; -24 .. 25)
            {
                auto utc = SysTime(dstSwitches[i][0] + dur!"hours"(hour), UTC());
                auto local = utc.toOtherTZ(tz);

                void testOffset2(Duration offset, size_t line = __LINE__)
                {
                    AssertError msg(string tag)
                    {
                        return new AssertError(format("%s [%s] [%s]: [%s] [%s]", tag, hour, tz.name, utc, local),
                                               __FILE__, line);
                    }

                    enforce((utc + offset).hour == local.hour, msg("1"));
                    enforce((utc + offset + dur!"minutes"(1)).hour == local.hour, msg("2"));
                }

                if (utc < springSwitch)
                    testOffset2(stdOffset);
                else
                    testOffset2(dstOffset);

                utc = SysTime(dstSwitches[i][1] + dur!"hours"(hour), UTC());
                local = utc.toOtherTZ(tz);

                if (utc == fallSwitch || utc == fallSwitchMinus1)
                {
                    if (first)
                    {
                        testOffset2(dstOffset);
                        first = false;
                    }
                    else
                        testOffset2(stdOffset);
                }
                else if (utc > fallSwitch)
                    testOffset2(stdOffset);
                else
                    testOffset2(dstOffset);
            }
        }
    }


    // @@@DEPRECATED_2017-07@@@
    /++
        $(RED Deprecated. Use either PosixTimeZone.getInstalledTZNames or
              WindowsTimeZone.getInstalledTZNames. ($(LREF parseTZConversions)
              can be used to convert time zone names if necessary). Microsoft
              changes their time zones too often for us to compile the
              conversions into Phobos and have them be properly up-to-date.
              TimeZone.getInstalledTZNames will be removed in July 2017.)

        Returns a list of the names of the time zones installed on the system.

        Providing a sub-name narrows down the list of time zones (which
        can number in the thousands). For example,
        passing in "America" as the sub-name returns only the time zones which
        begin with "America".

        On Windows, this function will convert the Windows time zone names to
        the corresponding TZ Database names with
        $(D windowsTZNameToTZDatabaseName). To get the actual Windows time
        zone names, use $(D WindowsTimeZone.getInstalledTZNames) directly.

        Params:
            subName = The first part of the time zones desired.

        Throws:
            $(D FileException) on Posix systems if it fails to read from disk.
            $(LREF DateTimeException) on Windows systems if it fails to read the
            registry.
      +/
    deprecated("Use PosixTimeZone.getInstalledTZNames or WindowsTimeZone.getInstalledTZNames instead")
    static string[] getInstalledTZNames(string subName = "") @safe
    {
        version(Posix)
            return PosixTimeZone.getInstalledTZNames(subName);
        else version(Windows)
        {
            import std.algorithm.searching : startsWith;
            import std.algorithm.sorting : sort;
            import std.array : appender;

            auto windowsNames = WindowsTimeZone.getInstalledTZNames();
            auto retval = appender!(string[])();

            foreach (winName; windowsNames)
            {
                auto tzName = windowsTZNameToTZDatabaseName(winName);
                if (tzName !is null && tzName.startsWith(subName))
                    retval.put(tzName);
            }

            sort(retval.data);
            return retval.data;
        }
    }

    deprecated @safe unittest
    {
        import std.exception : assertNotThrown;
        import std.stdio : writefln;
        static void testPZSuccess(string tzName)
        {
            scope(failure) writefln("TZName which threw: %s", tzName);
            TimeZone.getTimeZone(tzName);
        }

        auto tzNames = getInstalledTZNames();
        // This was not previously tested, and it's currently failing, so I'm
        // leaving it commented out until I can sort it out.
        //assert(equal(tzNames, tzNames.uniq()));

        foreach (tzName; tzNames)
            assertNotThrown!DateTimeException(testPZSuccess(tzName));
    }


protected:

    /++
        Params:
            name    = The name of the time zone.
            stdName = The abbreviation for the time zone during std time.
            dstName = The abbreviation for the time zone during DST.
      +/
    this(string name, string stdName, string dstName) @safe immutable pure
    {
        _name = name;
        _stdName = stdName;
        _dstName = dstName;
    }


private:

    immutable string _name;
    immutable string _stdName;
    immutable string _dstName;
}
