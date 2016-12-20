package Koha::Plugin::Com::ByWaterSolutions::PatronOverdueNotices;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use C4::Overdues qw(parse_overdues_letter);
use Koha::Database;

use open qw(:utf8);

## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Patron Overdue Notices',
    author          => 'Kyle M Hall',
    description     => 'Generate and print overdue notices for patrons.',
    date_authored   => '2016-06-20',
    date_updated    => '2016-06-20',
    minimum_version => '3.2000000',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'report' subroutine means the plugin is capable
## of running a report. The difference between a report and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a report
sub report {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('submit') ) {
        $self->report_step1();
    }
    else {
        $self->report_step2();
    }

}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

sub report_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'report-step1.tt' } );

    print $cgi->header();
    print $template->output();
}

sub report_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $branchcode        = scalar $cgi->param('branchcode');
    my $days_from         = scalar $cgi->param('days_from');
    my $days_to           = scalar $cgi->param('days_to');
    my $patron_cardnumber = scalar $cgi->param('cardnumber');
    my $patron_id         = scalar $cgi->param('borrowernumber');
    my $notice_code       = scalar $cgi->param('notice_code');
    my @categorycodes     = $cgi->multi_param('categorycode');

    ( $days_from, $days_to ) = ( $days_to, $days_from )
      if ( $days_to > $days_from );

    @categorycodes = map { qq{'$_'} } @categorycodes;
    my $categorycodes = join( ',', @categorycodes );

    my $dbh   = C4::Context->dbh();
    my $query = qq{
        SELECT biblio.*, items.*, issues.*, biblioitems.itemtype, branches.branchname, borrowers.branchcode AS patron_branchcode,
               borrowers.cardnumber, borrowers.surname, borrowers.firstname, borrowers.email, borrowers.phone, borrowers.borrowernumber,borrowers.cardnumber,borrowers.address,borrowers.address2,borrowers.city,borrowers.zipcode
        FROM issues, items, biblio, biblioitems, branches, borrowers
        WHERE items.itemnumber=issues.itemnumber
          AND biblio.biblionumber   = items.biblionumber
          AND branches.branchcode   = items.homebranch
          AND biblio.biblionumber   = biblioitems.biblionumber
          AND borrowers.borrowernumber = issues.borrowernumber
    };

    my @params;

    if ( $days_from && $days_to ) {
        $query .= qq{ AND date_due BETWEEN DATE_SUB(CURDATE(), INTERVAL ? DAY) AND DATE_SUB(CURDATE(), INTERVAL ? DAY) };
        push( @params, $days_from );
        push( @params, $days_to );
    } else {
        $query .= qq{ AND date_due < NOW() };
    }

    if ( $branchcode ) {
        $query .= qq{ AND issues.branchcode = ? };
        push( @params, $branchcode );
    }

    if (@categorycodes) {
        $query .= qq{ AND borrowers.categorycode IN ( $categorycodes ) };
    }

    if ( $patron_id ) {
        $query .= qq{ AND borrowers.borrowernumber = ? };
        push( @params, $patron_id );
    }
    elsif ( $patron_cardnumber ) {
        $query .= qq{ AND borrowers.cardnumber = ? };
        push( @params, $patron_cardnumber );
    }

    $query .= qq{ ORDER BY surname, firstname, cardnumber };

    my $sth = $dbh->prepare($query);
    $sth->execute(@params);

    my $overdues;
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) {
        push( @rows, $row );

        my $borrowernumber = $row->{borrowernumber};
        $overdues->{$borrowernumber} ||= [];
        push( @{ $overdues->{$borrowernumber} }, $row );
    }

    my @notices;
    foreach my $borrowernumber ( keys %$overdues ) {

        my $notice = parse_overdues_letter(
            {
                message_transport_type => 'print',
                letter_code            => $notice_code,
                borrowernumber         => $borrowernumber,
                branchcode =>
                  $overdues->{$borrowernumber}->[0]->{patron_branchcode},
                items      => $overdues->{$borrowernumber},
                substitute => {
                    count => scalar @{ $overdues->{$borrowernumber} },
                },
            }
        );

        push( @notices, $notice );
    }

    my $template = $self->get_template( { file => 'report-step2.tt' } );
    $template->param(
        notices  => \@notices,
        rows     => \@rows,
        overdues => $overdues,
    );

    print $cgi->header();
    print $template->output();
}

1;
