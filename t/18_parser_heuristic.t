#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Date::Reformat;

# For additional test cases, see the PostgreSQL regression test: src/test/regress/expected/date.out
# https://github.com/postgres/postgres/blob/master/src/test/regress/expected/date.out

my @TESTS = (
    {
        'date_string' => '2015-01-14 21:07:31',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '2015',
            'month'  => '01',
            'day'    => '14',
            'hour'   => '21',
            'minute' => '07',
            'second' => '31',
        },
    },
    {
        'date_string' => 'Wed Jan 14 21:07:31 2015',
        'parser' => {
            'heuristic' => 'mdy',
        },
        'expected' => {
            'day_abbr'    => 'Wed',
            'month_abbr'  => 'Jan',
            'day'         => '14',
            'hour'        => '21',
            'minute'      => '07',
            'second'      => '31',
            'year'        => '2015',
        },
    },
    {
        'date_string' => '1/14/2015 9:07:31 pm',
        'parser' => {
            'heuristic' => 'mdy',
        },
        'expected' => {
            'month'    => '1',
            'day'      => '14',
            'year'     => '2015',
            'hour_12'  => '9',
            'minute'   => '07',
            'second'   => '31',
            'am_or_pm' => 'pm',
        },
    },
    {
        'date_string' => '20150114T210731',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '2015',
            'month'  => '01',
            'day'    => '14',
            'hour'   => '21',
            'minute' => '07',
            'second' => '31',
        },
    },

    # Test expansion and special characters
    {
        'date_string' => '2015-01-14 T% 21:07:31',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '2015',
            'month'  => '01',
            'day'    => '14',
            'hour'   => '21',
            'minute' => '07',
            'second' => '31',
        },
    },

    # Tests from the PostgreSQL regression test: src/test/regress/expected/date.out
    # ymd
    {
        'date_string' => 'January 8, 1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month_name'  => 'January',
            'day'         => '8',
        },
    },
    {
        'date_string' => '1999-01-08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '1999',
            'month'  => '01',
            'day'    => '08',
        },
    },
    {
        'date_string' => '1999-01-18',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '1999',
            'month'  => '01',
            'day'    => '18',
        },
    },
    {
        'date_string' => '1/8/1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '1/18/1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '18/1/1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '01/02/03',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr' => '01',
            'month'     => '02',
            'day'       => '03',
        },
    },
    {
        'date_string' => '19990108',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'   => '1999',
            'month'  => '01',
            'day'    => '08',
        },
    },
    {
        'date_string' => '990108',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr' => '99',
            'month'     => '01',
            'day'       => '08',
        },
    },
    {
        'date_string' => '1999.008',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'day_of_year' => '008',
        },
    },
    {
        'date_string' => 'J2451187',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'julian_day'  => '2451187',
        },
    },
    {
        'date_string' => 'January 8, 99 BC',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99-Jan-08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'month_abbr'  => 'Jan',
            'day'         => '08',
        },
    },
    {
        'date_string' => '1999-Jan-08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month_abbr'  => 'Jan',
            'day'         => '08',
        },
    },
    {
        'date_string' => 'Jan-08-99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99-08-Jan',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '1999-08-Jan',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99 Jan 08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'month_abbr'  => 'Jan',
            'day'         => '08',
        },
    },
    {
        'date_string' => '1999 Jan 08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month_abbr'  => 'Jan',
            'day'         => '08',
        },
    },
    {
        'date_string' => '08 Jan 99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => 'Jan 08 99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99 08 Jan',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'day'         => '08',
            'month_abbr'  => 'Jan',
        },
    },
    {
        'date_string' => '1999 08 Jan',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'day'         => '08',
            'month_abbr'  => 'Jan',
        },
    },
    {
        'date_string' => '99-01-08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'month'       => '01',
            'day'         => '08',
        },
    },
    {
        'date_string' => '1999-01-08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month'       => '01',
            'day'         => '08',
        },
    },
    {
        'date_string' => '08-01-99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '08-01-1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '01-08-99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '01-08-1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99-08-01',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'month'       => '08',
            'day'         => '01',
        },
    },
    {
        'date_string' => '1999-08-01',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month'       => '08',
            'day'         => '01',
        },
    },
    {
        'date_string' => '99 01 08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'month'       => '01',
            'day'         => '08',
        },
    },
    {
        'date_string' => '1999 01 08',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'month'       => '01',
            'day'         => '08',
        },
    },
    {
        'date_string' => '08 01 99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '08 01 1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '01 08 99',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '01 08 1999',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => undef,
    },
    {
        'date_string' => '99 08 01',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year_abbr'   => '99',
            'day'         => '01',
            'month'       => '08',
        },
    },
    {
        'date_string' => '1999 08 01',
        'parser' => {
            'heuristic' => 'ymd',
        },
        'expected' => {
            'year'        => '1999',
            'day'         => '01',
            'month'       => '08',
        },
    },
);

plan('tests' => scalar(@TESTS));

foreach my $test (@TESTS) {
    # Set up the parser.
    my $parser = Date::Reformat->new(
        'parser'    => $test->{'parser'},
        'formatter' => {
            'data_structure' => 'hashref',
        },
        'debug'     => 1,
    );

    # Parse the date string.
    my $reformatted = $parser->parse_date($test->{'date_string'});

    # Verify the result is what we expect.
    is_deeply(
        $reformatted,
        $test->{'expected'},
        "Verify parsing of: $test->{'date_string'}",
    );
}
