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

    my $reformatted_string = $parser->parse_date($date_string);

=head1 DESCRIPTION

This module aims to be a lightweight and flexible tool for rearranging
components of a date string, then returning the components in the order
and structure specified.

=cut

use 5.010000;
use strict;
use warnings;

our $VERSION = '0.01';

my $TOKENS = {
    'year' => {
        'regex'   => q/(?<year>\d{4})/,
        'sprintf' => '%04d',
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
    'day' => {
        'regex'   => q/(?<day>\d\d?)/,
        'sprintf' => '%02d',
    },
    'hour' => {
        'regex'   => q/(?<hour>\d\d?)/,
        'sprintf' => '%02d',
    },
    'minute' => {
        'regex'   => q/(?<minute>\d\d?)/,
        'sprintf' => '%02d',
    },
    'second' => {
        'regex'   => q/(?<second>\d\d?)/,
        'sprintf' => '%02d',
    },
    'day_abbr' => {
        'regex'   => q/(?<day_abbr>Mon|Tues?|Wed|Thur?|Fri|Sat|Sun)/,
        'sprintf' => '%s',
    },
    'month_abbr' => {
        'regex'   => q/(?<month_abbr>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/,
        'sprintf' => '%s',
    },
    'am_or_pm' => {
        'regex'   => q/(?<am_or_pm>(?)[ap]\.?m\.?)/,
        'sprintf' => '%s',
    },
    'hour_12' => {
        'regex'   => q/(?<hour_12>\d\d?)/,
        'sprintf' => '%d',
    },
    'time_zone' => {
        'regex'   => q|(?<time_zone>\w+(?:/\w+))|,
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
    '%j' => 'day_of_year', # TODO
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
    '%y' => 'year_abbr', # TODO
    '%Z' => 'time_zone', # TODO
    '%z' => 'time_zone_offset', # TODO
};

my $DEFAULT_STRFTIME_MAPPINGS = {
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
                map { $_ // '' } @{$date}{@$params},
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
