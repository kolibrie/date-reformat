#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use IO::File;
use Text::CSV;
use Date::Reformat;

my $PARAMS = {};
GetOptions(
    $PARAMS,
    'target_format=s',
    'source_format=s',
    'reformat_column=s@',
    'help|h!',
);

if ($PARAMS->{'help'}) {
    usage();
}

sub usage {
    print "Usage: $0 --source_format STRPTIME --reformat_column NAME < INPUT_FILENAME.CSV\n";
    print "    --source_format    A strptime format that matches the date string format in the file\n";
    print "                       (May also be the string 'heuristic:ymd', or ...:mdy, or ...:dmy)\n";
    print "    --target_format    A strftime format that describes how the date should be formatted\n";
    print "                       (Default is '%Y-%m-%d')\n";
    print "    --reformat_column  The column name of the date column to reformat\n";
    print "                       (May be specified more than once)\n";
    print "    --help|-h          Prints out this usage information\n";
    print "\n";
    exit;
}

my $filename = shift(@ARGV);

# Set up date parsing and formatting.

my $formatter_instructions = { 'strftime' => ($PARAMS->{'target_format'} || '%Y-%m-%d') };
my $parser_instructions = { 'strptime' => $PARAMS->{'source_format'} };
if ($PARAMS->{'source_format'} =~ m/^heuristic:(ymd|dmy|mdy)$/) {
    $parser_instructions = { 'heuristic' => $1 };
}

my $date_reformatter = Date::Reformat->new(
    'parser'    => $parser_instructions,
    'formatter' => $formatter_instructions,
);

# Set up CSV reading and writing.

my ($input_iterator, $output_iterator) = csv_iterator($filename);

# Do the work.

while (my $row = $input_iterator->()) {
    foreach my $column (@{$PARAMS->{'reformat_column'}}) {
        $row->{$column} = $date_reformatter->reformat_date($row->{$column});
    }
    $output_iterator->($row);
}

# Helper functions.

sub csv_iterator {
    my ($filename) = @_;
    my $fh = IO::File->new();
    if ($filename) {
        $fh->open($filename, 'r') || die "Failed to read file $filename: $!\n";
    }
    else {
        $fh->fdopen(fileno(STDIN), 'r') || die "Failed to read from STDIN: $!\n";
    }
    my $csv_in = Text::CSV->new();
    my $columns = $csv_in->getline($fh);
    $csv_in->column_names(@$columns);
    my $csv_out = Text::CSV->new();
    return (
        # Input.
        sub {
            my $row = $csv_in->getline_hr($fh);
            return if ! defined $row;
            return $row;
        },
        # Output.
        sub {
            my ($row) = @_;
            $csv_out->combine(@{$row}{@$columns});
            print $csv_out->string() . "\n";
        }
    );
}
