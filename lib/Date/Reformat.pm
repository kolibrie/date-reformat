package Date::Reformat;

=head1 NAME

Date::Reformat - Rearrange date strings

=head1 SYNOPSIS

    use Date::Reformat;

    my $parser = Date::Reformat->new(
        parser => {
            regex  => qr/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)$/,
            params => [qw(year month day hour minute second)],
        },
        defaults => {
            time_zone => 'America/New_York',
        },
        transformations => [
            {
                from    => 'year',
                to      => 'century',
                coderef => sub { int($_[0] / 100) },
            },
        ],
        formatter => {
            sprintf => '%s-%02d-%02dT%02d:%02d:02d %s',
            params  => [qw(year month day hour minute second time_zone)],
        },
    );

    my $parser = Date::Reformat->new(
        parser => {
            strptime => '%Y-%m-%dT%M:%H:%S',
            # or heuristic => 'ymd', # http://www.postgresql.org/docs/9.2/static/datetime-input-rules.html
        },
        defaults => {
            time_zone => 'America/New_York',
        },
        formatter => {
            strftime => '%Y-%m-%dT%M:%H:%S %Z',
            # or data_structure => 'hashref' || 'hash' || 'arrayref' || 'array'
            # or coderef => sub { my ($y, $m, $d) = @_; DateTime->new(year => $y, month => $m, day => $d) },
            # params => [qw(year month day)],
        },
    );

    my $reformatted_string = $parser->reformat_date($date_string);

=head1 DESCRIPTION

This module aims to be a lightweight and flexible tool for rearranging
components of a date string, then returning the components in the order
and structure specified.

=cut

use 5.010000;
use strict;
use warnings;

our $VERSION = '0.01';

my $MONTH_LOOKUP = {
};
{
    # Lookups for month abbreviations.
    my $c = 0;
    foreach my $abbr (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)) {
        $MONTH_LOOKUP->{'abbr'}->{lc($abbr)} = ++$c;
        $MONTH_LOOKUP->{'number'}->{$c}->{'abbr'} = $abbr;
    }
}

my $TOKENS = {
    'year' => {
        'regex'   => q/(?<year>\d{4})/,
        'sprintf' => '%04d',
    },
    'year_abbr' => {
        'regex'   => q/(?<year>\d{2})/,
        'sprintf' => '%02d',
    },
    'month' => {
        'regex'   => q/(?<month>\d\d?)/,
        'sprintf' => '%02d',
    },
    'month_no_padding' => {
        'regex'   => q/(?<month>\d\d?)/,
        'sprintf' => '%d',
        'storage' => 'month',
    },
    'month_name' => {
        'regex'   => q/(?<month_name>January|February|March|April|May|June|July|August|September|October|November|December)/,
        'sprintf' => '%s',
    },
    'month_abbr' => {
        'regex'   => q/(?<month_abbr>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/,
        'sprintf' => '%s',
    },
    'day' => {
        'regex'   => q/(?<day>\d\d?)/,
        'sprintf' => '%02d',
    },
    'day_name' => {
        'regex'   => q/(?<day_name>Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)/,
        'sprintf' => '%s',
    },
    'day_abbr' => {
        'regex'   => q/(?<day_abbr>Mon|Tues?|Wed|Thur?|Fri|Sat|Sun)/,
        'sprintf' => '%s',
    },
    'day_of_year' => {
        'regex'   => q/(?<day_of_year>\d\d?\d?)/,
        'sprintf' => '%03d',
    },
    'hour' => {
        'regex'   => q/(?<hour>\d\d?)/,
        'sprintf' => '%02d',
    },
    'hour_12' => {
        'regex'   => q/(?<hour_12>\d\d?)/,
        'sprintf' => '%d',
    },
    'minute' => {
        'regex'   => q/(?<minute>\d\d)/,
        'sprintf' => '%02d',
    },
    'second' => {
        'regex'   => q/(?<second>\d\d)/,
        'sprintf' => '%02d',
    },
    'am_or_pm' => {
        'regex'   => q/(?<am_or_pm>(?i)[ap]\.?m\.?)/,
        'sprintf' => '%s',
    },
    'time_zone' => {
        'regex'   => q|(?<time_zone>\w+(?:/\w+))|,
        'sprintf' => '%s',
    },
    'phrase' => {
        'regex'   => q/(?<phrase>(?i)today|tomorrow|yesterday|(?:next|last)\w+(?:week|month|year)|\d+\w+(?:seconds?|minutes?|hours?|days?|weeks?|months?|years?)\w+(?:ago|from\w+now))/,
        'sprintf' => '%s',
    },
};

my $STRPTIME_PREPROCESS = [
    {
        'token'       => '%c',
        'replacement' => '%c', # TODO: Perhaps use Scalar::Defer, and look up locale datetime format only if needed.
    },
    {
        'token'       => '%D',
        'replacement' => '%m/%d/%y',
    },
    {
        'token'       => '%F',
        'replacement' => '%Y-%m-%d',
    },
    {
        'token'       => '%R',
        'replacement' => '%H:%M',
    },
    {
        'token'       => '%r',
        'replacement' => '%I:%M:%S %p', # TODO: This may be affected by locale.
    },
    {
        'token'       => '%T',
        'replacement' => '%H:%M:%S',
    },
    {
        'token'       => '%X',
        'replacement' => '%X', # TODO: Perhaps use Scalar::Defer, and look up locale time format only if needed.
    },
    {
        'token'       => '%x',
        'replacement' => '%x', # TODO: Perhaps use Scalar::Defer, and look up locale date format only if needed.
    },
];

my $STRPTIME_POSTPROCESS = [
    {
        'token'       => '%n',
        'replacement' => '\s+',
    },
    {
        'token'       => '%t',
        'replacement' => '\s+',
    },
    {
        'token'       => '%%',
        'replacement' => quotemeta('%'),
    },
];

my $STRFTIME_POSTPROCESS = [
    {
        'token'       => '%n',
        'replacement' => "\n",
    },
    {
        'token'       => '%t',
        'replacement' => "\t",
    },
];

my $DEFAULT_STRPTIME_MAPPINGS = {
    '%A' => 'day_name', # TODO
    '%a' => 'day_abbr',
    '%B' => 'month_name', # TODO
    '%b' => 'month_abbr',
    '%C' => 'century', # TODO
    '%d' => 'day',
    '%e' => 'day', # TODO: This one is space-padded.
    '%G' => 'week_year', # TODO
    '%g' => 'week_year_abbr', # TODO
    '%H' => 'hour',
    '%h' => 'month_abbr',
    '%I' => 'hour_12',
    '%j' => 'day_of_year',
    '%k' => 'hour', # TODO: This one is space-padded.
    '%l' => 'hour_12', # TODO: This one is space-padded.
    '%M' => 'minute',
    '%m' => 'month',
    '%-m' => 'month_no_padding',
    '%N' => 'fractional_seconds', # TODO
    '%P' => 'am_or_pm',
    '%p' => 'am_or_pm', # TODO: This is uppercase.
    '%S' => 'second',
    '%s' => 'epoch', # TODO
    '%U' => 'week_number_0', # TODO
    '%u' => 'day_of_week', # TODO
    '%V' => 'week_number', # TODO
    '%W' => 'week_number_1', # TODO
    '%w' => 'day_of_week_0', # TODO
    '%Y' => 'year',
    '%y' => 'year_abbr',
    '%Z' => 'time_zone', # TODO
    '%z' => 'time_zone_offset', # TODO
};

my $DEFAULT_STRFTIME_MAPPINGS = {
};

my $DEFAULT_TRANSFORMATIONS = {
    # to => {
    #   from => \&transformation_coderef,
    # },
    'year' => {
        'year_abbr' => sub {
            my ($date) = @_;
            return $date->{'year'} if defined($date->{'year'});
            return $date->{'year_abbr'} < 70
                ? $date->{'year_abbr'} + 2000
                : $date->{'year_abbr'} + 1900;
        },
    },
    'year_abbr' => {
        'year' => sub {
            my ($date) = @_;
            return $date->{'year_abbr'} if defined($date->{'year_abbr'});
            return substr($date->{'year'}, -2, 2);
        },
    },
    'month' => {
        'month_abbr' => sub {
            my ($date) = @_;
            return $date->{'month'} if defined($date->{'month'});
            return $MONTH_LOOKUP->{'abbr'}->{ lc($date->{'month_abbr'}) } // undef;
        },
    },
    'month_abbr' => {
        'month' => sub {
            my ($date) = @_;
            return $date->{'month_abbr'} if defined($date->{'month_abbr'});
            return $MONTH_LOOKUP->{'number'}->{ $date->{'month'}+0 }->{'abbr'} // undef;
        },
    },
    'hour' => {
        'hour_12' => sub {
            my ($date) = @_;
            return $date->{'hour'} if defined($date->{'hour'});
            if (lc($date->{'am_or_pm'}) eq 'pm') {
                return $date->{'hour_12'} == 12
                    ? $date->{'hour_12'}
                    : $date->{'hour_12'} + 12;
            }
            return $date->{'hour_12'} == 12
                ? 0
                : $date->{'hour_12'};
        },
    },
    'hour_12' => {
        'hour' => sub {
            my ($date) = @_;
            return $date->{'hour_12'} if defined($date->{'hour_12'});
            if ($date->{'hour'} == 0) {
                return 12;
            }
            return $date->{'hour'} < 13
                ? $date->{'hour'}
                : $date->{'hour'} - 12;
        },
    },
    'am_or_pm' => {
        'hour' => sub {
            my ($date) = @_;
            return $date->{'am_or_pm'} if defined($date->{'am_or_pm'});
            if ($date->{'hour'} == 0) {
                return 'am';
            }
            return $date->{'hour'} >= 12
                ? 'pm'
                : 'am';
        },
    },
};

=head2 METHODS

=over 4

=item new()

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    foreach my $parameter (
        'debug',
        'parser',
        'formatter',
        'transformations',
        'defaults',
    )
    {
        my $method = 'initialize_' . $parameter;
        $self->$method($args{$parameter});
    }
    return $self;
}

=item initialize_parser()

=cut

sub initialize_parser {
    my ($self, $definition) = @_;
    # TODO: Verify $definition is a hashref with one of the approved parser parameters (regex, strptime, etc.).
    if (defined($definition->{'regex'})) {

        # Initialize the right kind of regex parser (simple capture or named capture).
        if (defined($definition->{'params'})) {
            return $self->initialize_parser_for_regex_with_params(
                {
                    'regex'  => $definition->{'regex'},
                    'params' => $definition->{'params'},
                }
            );
        }
        return $self->initialize_parser_for_regex_named_capture(
            {
                'regex' => $definition->{'regex'},
            },
        );

    }

    if (defined($definition->{'strptime'})) {
        return $self->initialize_parser_for_strptime(
            {
                'strptime' => $definition->{'strptime'},
            },
        );
    }

    if (defined($definition->{'heuristic'})) {
        return $self->initialize_parser_heuristic(
            {
                'heuristic' => $definition->{'heuristic'},
            },
        );
    }

    # Nothing initialized.
    return;
}

=item initialize_formatter()

=cut

sub initialize_formatter {
    my ($self, $definition) = @_;
    # TODO: Verify $definition is a hashref with one of the approved formatter parameters (sprintf, strftime, etc.).
    if (defined($definition->{'sprintf'})) {
        return $self->initialize_formatter_for_sprintf(
            {
                'sprintf' => $definition->{'sprintf'},
                'params'  => $definition->{'params'},
            },
        );
    }

    if (defined($definition->{'strftime'})) {
        return $self->initialize_formatter_for_strftime(
            {
                'strftime' => $definition->{'strftime'},
            },
        );
    }

    # Nothing initialized.
    return;
}

=item initialize_transformations()

=cut

sub initialize_transformations {
    my ($self, $transformations) = @_;
    # TODO: Verify $transformations is an arrayref.
    my $count = 0;
    foreach my $t (@$transformations) {
        $self->{'transformations'}->{$t->{'to'}}->{$t->{'from'}} = $t->{'transformation'};
        $count++;
    }
    return $count;
}

=item initialize_defaults()

=cut

sub initialize_defaults {
    my ($self, $args) = @_;
    # TODO: Verify $args is a hashref.
    return $self->{'defaults'} = $args // {};
}

=item initialize_debug()

=cut

sub initialize_debug {
    my ($self, $value) = @_;
    return $self->{'debug'} = $value // 0;
}

=item initialize_parser_for_regex_with_params()

=cut

sub initialize_parser_for_regex_with_params {
    my ($self, $definition) = @_;
    my $regex = $definition->{'regex'};
    my $params = $definition->{'params'};
    my $success = $self->add_parser(
        sub {
            my ($date_string) = @_;
            my (@components) = $date_string =~ $regex;
            return if ! @components;
            my %date = ();
            @date{@$params} = @components;
            # TODO: Add named capture values to %date.
            return \%date;
        },
    );
    return $success;
}

=item initialize_parser_for_regex_named_capture()

=cut

sub initialize_parser_for_regex_named_capture {
    my ($self, $definition) = @_;
    my $regex = $definition->{'regex'};
    my $success = $self->add_parser(
        sub {
            my ($date_string) = @_;
            my $success = $date_string =~ $regex;
            return if ! $success;
            my %date = %+;

            # Move 'hour_12' if the wrong value.
            if (
                defined($date{'hour_12'})
                &&
                (
                    $date{'hour_12'} > 12
                    ||
                    $date{'hour_12'} == 0
                )
            ) {
                $date{'hour'} = delete $date{'hour_12'};
            }

            return \%date;
        },
    );
    return $success;
}

=item initialize_parser_for_strptime()

=cut

sub initialize_parser_for_strptime {
    my ($self, $definition) = @_;
    my $strptime = $definition->{'strptime'};
    my $format = $strptime;

    # Preprocess some tokens that expand into other tokens.
    foreach my $preprocess (@$STRPTIME_PREPROCESS) {
        $format =~ s/$preprocess->{'token'}/$preprocess->{'replacement'}/g;
    }

    # Escape everything in the strptime string so we can turn it into a regex.
    $format = quotemeta($format);

    # Unescape the parts that we will replace as tokens.
    # regex from DateTime::Format::Strptime
    $format =~ s/(?<!\\)\\%/%/g;
    $format =~ s/%\\\{([^\}]+)\\\}/%{$1}/g;

    # Replace expanded tokens: %{year}
    $format =~
        s/
            %{(\w+)}
        /
            $TOKENS->{$1} ? $TOKENS->{$1}->{'regex'} : "\%{$1}"
        /sgex;

    # Replace single character tokens: %Y
    $format =~
        s/
            (%[%a-zA-Z])
        /
            $self->strptime_token_to_regex($1)
        /sgex;

    # Postprocess some tokens that expand into special characters.
    foreach my $postprocess (@$STRPTIME_POSTPROCESS) {
        $format =~ s/$postprocess->{'token'}/$postprocess->{'replacement'}/g;
    }

    say "Crafted regex: $strptime -> $format" if $self->{'debug'};
    my $success = $self->initialize_parser_for_regex_named_capture(
        {
            'regex' => qr/$format/,
        },
    );
    return $success;
}

=item initialize_parser_heuristic()

=cut

sub initialize_parser_heuristic {
    my ($self, $definition) = @_;
    my $hint = $definition->{'heuristic'};
    my $known_parsers = {}; # Populated when we add a parser to the stack in front of this one.
    my $regex_for_date = qr{ \w+ [-/\.] \w+ (?:[-/\.] \w+) }x;
    my $regex_for_time = qr/ \d\d? : \d\d (?::\d\d) /x;
    my $regex_for_time_zone_offset = qr/ [-+] \d\d? (?:\d\d) /x;
    my $regex_for_time_zone_long_name = qr{ [[:alpha:]]+ / [[:alpha:]]+ (?:_ [[:alpha:]]+) }x;
    my $regex_for_number = qr/ \d+ /x;
    my $regex_for_string = qr/ [[:alpha:]]+ /x;
    my $regex_for_whitespace = qr/ \s+ /x;
    my $token_regex = qr{
        # time zone offset
        ( $regex_for_time_zone_offset )
        # time
        | ( $regex_for_time )
        # time zone long name
        | ( $regex_for_time_zone_long_name )
        # date
        | ( $regex_for_date )
        # number
        | ( $regex_for_number )
        # string
        | ( $regex_for_string )
        # whitespace
        | ( $regex_for_whitespace )
        # anything else
        | ( . )
    }x;
    my $success = $self->add_parser(
        sub {
            my ($date_string) = @_;
            my $order_string; # Will be set with ymd|dmy|mdy when we have enough information.

            # Split string into parts that can be identified later.
            say "Parsing date string into parts: $date_string" if $self->{'debug'};
            my @parts = $date_string =~ /$token_regex/g;
            return if ! @parts;

            # Try to identify what each part is, based on what it looks like, and what order it is in.
            my @parser_parts = ();
            my $date = {};
            foreach my $part (grep { defined($_) } @parts) {
                say "Trying to identify part: '$part'" if $self->{'debug'};
                if ($part =~ $regex_for_time_zone_offset) {
                    say "  time_zone_offset ($part)" if $self->{'debug'};
                    push @parser_parts, $TOKENS->{'time_zone_offset'}->{'regex'};
                    $date->{'time_zone_offset'} = $part;
                }
                elsif ($part =~ $regex_for_time) {
                    my @time = split(/:/, $part);

                    say "  hour ($time[0])" if $self->{'debug'};
                    push @parser_parts, $TOKENS->{'hour'}->{'regex'};
                    $date->{'hour'} = $time[0];

                    say "  minute ($time[1])" if $self->{'debug'};
                    push @parser_parts, quotemeta(':'), $TOKENS->{'minute'}->{'regex'};
                    $date->{'minute'} = $time[1];

                    if (@time > 2) {
                        say "  second ($time[2])" if $self->{'debug'};
                        push @parser_parts, quotemeta(':'), $TOKENS->{'second'}->{'regex'};
                        $date->{'second'} = $time[2];
                    }
                }
                elsif ($part =~ $regex_for_time_zone_long_name) {
                    say "  time_zone ($part)";
                    push @parser_parts, $TOKENS->{'time_zone'}->{'regex'};
                    $date->{'time_zone'} = $part;
                }
                elsif ($part =~ $regex_for_date) {
                    my @date_parts = split(m|[-/\.]|, $part);
                    my @order = ();
                    foreach my $index (0..2) {
                        if ($date_parts[$index] =~ /^\d+$/) {
                            if ($date_parts[$index] > 31) {
                                $order[$index] = 'y';
                            }
                            elsif ($date_parts[$index] > 12) {
                                $order[$index] = 'd';
                            }
                            else {
                                $order[$index] = 'm';
                            }
                        }
                        elsif ($date_parts[$index] =~ $TOKENS->{'month_abbr'}->{'regex'}) {
                            $order[$index] = 'm';
                        }
                    }
                    $order_string = join('', @order);
                    if ($order_string !~ /^ymd|dmy|mdy$/) {
                        say "Using date token order hint: $hint" if $self->{'debug'};
                        $order_string = $hint;
                    }
                    @order = split(//, $order_string);
                    foreach my $index (0..2) {
                        if ($order[$index] eq 'y') {
                            if ($date_parts[$index] !~ $TOKENS->{'year'}->{'regex'}) {
                                warn "Error parsing year\n";
                            }
                            say "  year ($date_parts[$index])" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'year'}->{'regex'};
                            $date->{'year'} = $date_parts[$index];
                        }
                        elsif ($order[$index] eq 'm') {
                            if ($date_parts[$index] =~ $TOKENS->{'month'}->{'regex'}) {
                                say "  month ($date_parts[$index])" if $self->{'debug'};
                                push @parser_parts, $TOKENS->{'month'}->{'regex'};
                                $date->{'month'} = $date_parts[$index];
                            }
                            elsif ($date_parts[$index] =~ $TOKENS->{'month_abbr'}->{'regex'}) {
                                say "  month_abbr ($date_parts[$index])" if $self->{'debug'};
                                push @parser_parts, $TOKENS->{'month_abbr'}->{'regex'};
                                $date->{'month_abbr'} = $date_parts[$index];
                            }
                            else {
                                warn "Error parsing month\n";
                            }
                        }
                        elsif ($order[$index] eq 'd') {
                            if ($date_parts[$index] !~ $TOKENS->{'day'}->{'regex'}) {
                                warn "Error parsing day\n";
                            }
                            say "  day ($date_parts[$index])" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'day'}->{'regex'};
                            $date->{'day'} = $date_parts[$index];
                        }
                        push @parser_parts, qr|[-/\.]| if $index < 2;
                    }
                }
                elsif ($part =~ /^$regex_for_number$/) {
                    if (length($part) == 8) {
                        my $regex_date =
                            qr/
                                $TOKENS->{'year'}->{'regex'}
                                $TOKENS->{'month'}->{'regex'}
                                $TOKENS->{'day'}->{'regex'}
                            /x;
                        my $success = $part =~ $regex_date;
                        my %ymd = %+;
                        foreach my $token ('year', 'month', 'day') {
                            say "  $token ($ymd{$token})";
                            push @parser_parts, $TOKENS->{$token}->{'regex'};
                            $date->{$token} = $ymd{$token};
                        }
                    }
                    elsif (length($part) == 6) {
                        if (defined($date->{'year'})) {
                            # This is a concatenated time: HHMM
                            my $regex_time =
                                qr/
                                    $TOKENS->{'hour'}->{'regex'}
                                    $TOKENS->{'minute'}->{'regex'}
                                    $TOKENS->{'second'}->{'regex'}
                                /x;
                            my $success = $part =~ $regex_time;
                            my %hms = %+;
                            foreach my $token ('hour', 'minute', 'second') {
                                say "  $token ($hms{$token})";
                                push @parser_parts, $TOKENS->{$token}->{'regex'};
                                $date->{$token} = $hms{$token};
                            }
                        }
                        else {
                            # This is a concatenated date: YYMMDD
                            my $regex_date =
                                qr/
                                    $TOKENS->{'year_abbr'}->{'regex'}
                                    $TOKENS->{'month'}->{'regex'}
                                    $TOKENS->{'day'}->{'regex'}
                                /x;
                            my $success = $part =~ $regex_date;
                            my %ymd = %+;
                            foreach my $token ('year_abbr', 'month', 'day') {
                                say "  $token ($ymd{$token})";
                                push @parser_parts, $TOKENS->{$token}->{'regex'};
                                $date->{$token} = $ymd{$token};
                            }
                        }
                    }
                    elsif (length($part) == 3 && defined($date->{'year'})) {
                        # day_of_year
                        say "  day_of_year ($part)" if $self->{'debug'};
                        push @parser_parts, $TOKENS->{'day_of_year'}->{'regex'};
                        $date->{'day_of_year'} = $part;
                    }
                    elsif (length($part) == 4) {
                        if (defined($date->{'year'})) {
                            # This is a concatenated time without seconds: HHMM
                            my $regex_time =
                                qr/
                                    $TOKENS->{'hour'}->{'regex'}
                                    $TOKENS->{'minute'}->{'regex'}
                                /x;
                            my $success = $part =~ $regex_time;
                            my %hm = %+;
                            foreach my $token ('hour', 'minute') {
                                say "  $token ($hm{$token})";
                                push @parser_parts, $TOKENS->{$token}->{'regex'};
                                $date->{$token} = $hm{$token};
                            }
                        }
                        else {
                            # year (if month and day have not been set, order is now ymd).
                            say "  year ($part)" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'year'}->{'regex'};
                            $date->{'year'} = $part;
                            $order_string ||= 'ymd';
                        }
                    }
                    else {
                        # Either month, or day, or year (based on $order_string or $hint or what has been set already).
                        if (defined($date->{'day'})) {
                            # TODO: Check that $order_string // $hint is dmy?
                            say "  month ($part)" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'month'}->{'regex'};
                            $date->{'month'} = $part;
                        }
                        elsif (
                            defined($date->{'month'})
                            ||
                            defined($date->{'month_abbr'})
                            ||
                            defined($date->{'month_name'})
                        ) {
                            # TODO: Check that $order_string // $hint is mdy|ymd?
                            say "  day ($part)" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'day'}->{'regex'};
                            $date->{'day'} = $part;
                        }
                        elsif (
                            ($order_string // $hint) eq 'dmy'
                            &&
                            ! defined($date->{'year'})
                        ) {
                            say "  day ($part) based on " . ($order_string // $hint) if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'day'}->{'regex'};
                            $date->{'day'} = $part;
                        }
                        elsif (
                            ($order_string // $hint) eq 'mdy'
                            &&
                            ! defined($date->{'year'})
                        ) {
                            say "  month ($part) based on " . ($order_string // $hint) if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'month'}->{'regex'};
                            $date->{'month'} = $part;
                        }
                        elsif (
                            ($order_string // $hint) eq 'ymd'
                            &&
                            (
                                ! defined($date->{'month'})
                                &&
                                ! defined($date->{'month_abbr'})
                                &&
                                ! defined($date->{'month_name'})
                            )
                        ) {
                            say "  year ($part) based on " . ($order_string // $hint) if $self->{'debug'};
                            push @parser_parts, $TOKENS->{'year'}->{'regex'};
                            $date->{'year'} = $part;
                        }
                        else {
                            say "  number ($part)" if $self->{'debug'};
                            push @parser_parts, $regex_for_number;
                        }
                    }
                }
                elsif ($part =~ $regex_for_string) {
                    # TODO: Look for time zone abbreviation.
                    my $found = 0;
                    foreach my $token ('am_or_pm', 'month_name', 'month_abbr', 'day_name', 'day_abbr', 'phrase') {
                        if ($part =~ $TOKENS->{$token}->{'regex'}) {
                            say "  $token ($part)" if $self->{'debug'};
                            push @parser_parts, $TOKENS->{$token}->{'regex'};
                            $date->{$token} = $part;
                            $found = 1;
                            last;
                        }
                    }
                    if (! $found) {
                        say "  literal ($part)" if $self->{'debug'};
                        push @parser_parts, quotemeta($part);
                    }
                }
                elsif ($part =~ $regex_for_whitespace) {
                    say "  whitespace ($part)" if $self->{'debug'};
                    push @parser_parts, $regex_for_whitespace;
                }
                else {
                    say "  literal ($part)" if $self->{'debug'};
                    push @parser_parts, quotemeta($part);
                }
            }

            # If am_or_pm is pm, and hour is < 12, change from hour to hour_12 (and the parser).
            if (defined($date->{'am_or_pm'}) && lc($date->{'am_or_pm'}) eq 'pm' ) {
                if (defined($date->{'hour'}) && $date->{'hour'} < 12) {
                    $date->{'hour_12'} = delete $date->{'hour'};
                    foreach my $parser_part (@parser_parts) {
                        if ($parser_part =~ /\?<hour>/) {
                            $parser_part =~ s/\?<hour>/?<hour_12>/;
                        }
                    }
                }
            }
            my $parser_regex = join('', @parser_parts);
            say "Crafted regex: $date_string -> $parser_regex" if $self->{'debug'};

            # Add a new parser that will match this date format.
            if (! defined($known_parsers->{$parser_regex}) ) {
                $known_parsers->{$parser_regex} = 1;
                $self->initialize_parser_for_regex_named_capture(
                    {
                        'regex' => qr/$parser_regex/,
                    },
                );
                # Move the heuristic parser to the last slot again.
                push(
                    @{ $self->{'active_parsers'} },
                    splice(
                        @{ $self->{'active_parsers'} }, -2, 1
                    ),
                );
            }

            return $date;
        },
    );
    return $success;
}

=item initialize_formatter_for_sprintf()

=cut

sub initialize_formatter_for_sprintf {
    my ($self, $definition) = @_;
    my $sprintf = $definition->{'sprintf'};
    my $params = $definition->{'params'} // die "Unable to create sprintf formatter: No 'params' argument defined.";
    # TODO: Validate parameters.
    my $success = $self->add_formatter(
        sub {
            my ($date) = @_;
            my $formatted = sprintf(
                $sprintf,
                map
                {
                    # Use the value, if available.
                    $date->{$_}
                    //
                    # Or see if we can determine the value by transforming another field.
                    $self->transform_token_value(
                        'target_token' => $_,
                        'date'         => $date,
                    )
                    //
                    # Or see if there is a default value for the field.
                    $self->{'defaults'}->{$_}
                    //
                    # Or just use a value of empty string.
                    ''
                }
                @$params,
            );
            return $formatted;
        },
    );
    return $success;
}

=item initialize_formatter_for_strftime()

=cut

sub initialize_formatter_for_strftime {
    my ($self, $definition) = @_;
    my $strftime = $definition->{'strftime'};
    my $format = $strftime;
    my $params = [];

    # Preprocess some tokens that expand into other tokens.
    foreach my $preprocess (@$STRPTIME_PREPROCESS) {
        $format =~ s/$preprocess->{'token'}/$preprocess->{'replacement'}/g;
    }

    # Replace single character tokens with expanded tokens: %Y -> %{year}
    $format =~
        s/
            (%[-_^]?[%a-zA-Z])
        /
            $self->strftime_token_to_internal($1)
        /sgex;

    # Find all tokens.
    my @tokens = $format =~ m/(%{\w+})/g;

    # Replace tokens in order, and build $params list.
    foreach my $token (@tokens) {
        # Replace expanded tokens: %{year}
        if ($token =~ m/%{(\w+)}/) {
            my $internal = $1;
            my $sprintf = $TOKENS->{$internal}->{'sprintf'} //
                die "Unable to find sprintf definition for token '$internal'";

            say "Internal token $internal maps to sprintf token '$sprintf'." if $self->{'debug'};
            $format =~ s/\Q$token\E/$sprintf/;
            my $alias;
            if (defined($TOKENS->{$internal}->{'storage'})) {
                $alias = $TOKENS->{$internal}->{'storage'};
            }
            push @$params, ($alias // $internal);
        }
    }

    # Postprocess some tokens that expand into special characters.
    foreach my $postprocess (@$STRFTIME_POSTPROCESS) {
        $format =~ s/$postprocess->{'token'}/$postprocess->{'replacement'}/g;
    }

    say "Crafted sprintf: $strftime -> $format [" . join(', ', @$params) . "]" if $self->{'debug'};
    my $success = $self->initialize_formatter_for_sprintf(
        {
            'sprintf' => $format,
            'params'  => $params,
        },
    );
    return $success;
}

=item strptime_token_to_regex()

=cut

sub strptime_token_to_regex {
    my ($self, $token) = @_;
    my $internal;
    say "Attempting to convert strptime token $token into a regex." if $self->{'debug'};
    if (defined($self->{'strptime_mappings'}->{$token})) {
        $internal = $self->{'strptime_mappings'}->{$token};
    }
    elsif (defined($DEFAULT_STRPTIME_MAPPINGS->{$token})) {
        $internal = $DEFAULT_STRPTIME_MAPPINGS->{$token};
    }

    if (! defined($internal)) {
        say "No mapping found" if $self->{'debug'};
        return $token;  # Perform no substitution.
    }

    if (! defined($TOKENS->{$internal}->{'regex'})) {
        die "Unable to find regex definition for token '$internal'";
    }
    say "Strptime token $token maps to internal token '$internal'." if $self->{'debug'};

    return $TOKENS->{$internal}->{'regex'};
}

=item strftime_token_to_internal

=cut

sub strftime_token_to_internal {
    my ($self, $token) = @_;
    my $internal;
    say "Attempting to convert strftime token $token into an internal token." if $self->{'debug'};
    if (defined($self->{'strftime_mappings'}->{$token})) {
        $internal = $self->{'strftime_mappings'}->{$token};
    }
    if (defined($self->{'strptime_mappings'}->{$token})) {
        $internal = $self->{'strptime_mappings'}->{$token};
    }
    elsif (defined($DEFAULT_STRFTIME_MAPPINGS->{$token})) {
        $internal = $DEFAULT_STRFTIME_MAPPINGS->{$token};
    }
    elsif (defined($DEFAULT_STRPTIME_MAPPINGS->{$token})) {
        $internal = $DEFAULT_STRPTIME_MAPPINGS->{$token};
    }

    if (! defined($internal)) {
        say "No mapping found" if $self->{'debug'};
        return '%' . $token;  # Perform no substitution, but escape token for sprintf.
    }

    if (! defined($TOKENS->{$internal}->{'sprintf'})) {
        die "Unable to find sprintf definition for token '$internal'";
    }
    say "Strftime token $token maps to internal token '$internal'." if $self->{'debug'};

    return '%{' . $internal . '}';
}

=item transform_token_value()

=cut

sub transform_token_value {
    my ($self, %args) = @_;
    my $target_token = $args{'target_token'};
    my $date = $args{'date'};

    # Return the value, if it is already set.
    return $date->{$target_token} if defined($date->{$target_token});

    foreach my $transformations ($self->{'transformations'}, $DEFAULT_TRANSFORMATIONS) {
        # Look up transformations to $target_token from a field that is defined in $date.
        if (defined($transformations->{$target_token})) {
            foreach my $source_token (keys %{$transformations->{$target_token}}) {
                if (defined($date->{$source_token}) && defined($transformations->{$target_token}->{$source_token})) {
                    # Run the transformation and return the value.
                    return $transformations->{$target_token}->{$source_token}->($date);
                }
            }
        }
    }

    return;
}

=item add_parser()

=cut

sub add_parser {
    my ($self, $parser) = @_;
    my $count = push @{ $self->{'active_parsers'} }, $parser;
    return $count ? 1 : 0;
}

=item add_formatter()

=cut

sub add_formatter {
    my ($self, $formatter) = @_;
    my $count = push @{ $self->{'active_formatters'} }, $formatter;
    return $count ? 1 : 0;
}

=item parse_date()

=cut

sub parse_date {
    my ($self, $date_string) = @_;
    foreach my $parser (@{ $self->{'active_parsers'} }) {
        my $date = $parser->($date_string);
        # TODO: Add formatting step here.
        return $date if defined($date);
    }
    # None of the parsers were able to extract the date components.
    return;
}

=item format_date()

=cut

sub format_date {
    my ($self, $date) = @_;
    my $formatted = $date;
    foreach my $formatter (@{ $self->{'active_formatters'} }) {
        $formatted = $formatter->($formatted);
    }
    return $formatted;
}

=item reformat_date()

=cut

sub reformat_date {
    my ($self, $date_string) = @_;
    my $date = $self->parse_date($date_string);
    my $formatted = $self->format_date($date);
    return $formatted;
};

=back

=cut

1;
__END__
=head1 SEE ALSO

=over 4

=item Date::Transform

=item Date::Parser

=item Date::Format

=item DateTime::Format::Flexible

=item DateTime::Format::Builder

=back

=head1 AUTHOR

Nathan Gray E<lt>kolibrie@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Nathan Gray

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
