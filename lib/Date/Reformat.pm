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

=cut

use 5.010000;
use strict;
use warnings;

our $VERSION = '0.01';

=head1 DESCRIPTION

This module aims to be a lightweight and flexible tool for rearranging
components of a date string, then returning the components in the order
and structure specified.

=head2 METHODS

=over 4

=item new()

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    foreach my $parameter (
        'parser',
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
        my $regex = $definition->{'regex'};

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

=item add_parser()

=cut

sub add_parser {
    my ($self, $parser) = @_;
    my $count = push @{ $self->{'active_parsers'} }, $parser;
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
