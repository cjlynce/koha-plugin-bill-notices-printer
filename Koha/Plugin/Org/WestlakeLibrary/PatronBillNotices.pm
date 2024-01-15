package Koha::Plugin::Org::WestlakeLibrary::PatronBillNotices;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use C4::Overdues qw(parse_overdues_letter);
use Koha::Database;

use open qw(:utf8);

## Here we set our plugin version
our $VERSION = "1.0.7";
our $MINIMUM_VERSION = "23.05";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Patron Bill Notices',
    author          => 'CJ Lynce',
    description     => 'Generate print bills for patrons - based on the print overdue notices by Kyle M. Hall',
    date_authored   => '2024-01-10',
    date_updated    => "2024-01-15",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    namespace       => 'billnotices',
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


sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            default_rep_days => $self->retrieve_data('default_rep_days'),
            default_patron_types => $self->retrieve_data('default_patron_types'),
            default_template => $self->retrieve_data('default_template'),
        );

        $self->output_html( $template->output() );
    }
    else {
        my @default_patron_types = $cgi->multi_param('default_patron_types');
	@default_patron_types = map { qq{'$_'} } @default_patron_types;

	$self->store_data(
            {
                default_rep_days => $cgi->param('default_rep_days'),
                default_patron_types => join( ',', @default_patron_types ),
                default_template => $cgi->param('default_template'),
            }
        );
        $self->go_home();
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
    
    $template->param(
    	default_rep_days => $self->retrieve_data('default_rep_days'),
	default_patron_types => $self->retrieve_data('default_patron_types'),
	default_template => $self->retrieve_data('default_template'),
    );

    print $cgi->header();
    print $template->output();
}

sub report_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $branchcode        = scalar $cgi->param('branchcode');
    my $branchcode_field  = scalar $cgi->param('branchcode_field');
    #my $days_from         = scalar $cgi->param('days_from');
    #my $days_to           = scalar $cgi->param('days_to');
    my $fines_from        = scalar $cgi->param('fines_from');
    my $fines_to          = scalar $cgi->param('fines_to');
    my $patron_cardnumber = scalar $cgi->param('cardnumber');
    my $patron_id         = scalar $cgi->param('borrowernumber');
    my $notice_code       = scalar $cgi->param('notice_code');
    my $filter_issues     = scalar $cgi->param('filter_issues');
    my $fromDate	  = scalar $cgi->param('fromDate');
    my $toDate		  = scalar $cgi->param('toDate');
    my @categorycodes     = $cgi->multi_param('categorycode');
    my @loststatuses      = $cgi->multi_param('loststatuses');
    my $default_patron_types = $self->retrieve_data('default_patron_types');

    #   ( $days_from, $days_to ) = ( $days_to, $days_from )
    #  if ( $days_to > $days_from );

    @categorycodes = map { qq{'$_'} } @categorycodes;
    my $categorycodes = join( ',', @categorycodes );

    @loststatuses = map { qq{'$_'} } @loststatuses;
    my $loststatuses = join( ',', @loststatuses );

    my $dbh   = C4::Context->dbh();
    my $query = qq{
        SELECT
            a.amountoutstanding,
            biblio.title,
            borrowers.zipcode,
            borrowers.address,
            borrowers.address2,
            borrowers.borrowernumber,
            borrowers.branchcode,
            borrowers.city,
            borrowers.email,
            borrowers.firstname,
            borrowers.surname,
            a.date as date_due,
            a.accountlines_id as issue_id,
            a.date as issuedate,
            items.barcode,
            items.biblionumber,
            items.holdingbranch,
            items.homebranch,
            items.itemcallnumber,
            items.itemnumber,
            items.replacementprice as price
FROM   accountlines a
       LEFT JOIN items
              ON ( a.itemnumber = items.itemnumber )
       LEFT JOIN biblio USING ( biblionumber )
       LEFT JOIN biblioitems USING ( biblioitemnumber )
       LEFT JOIN borrowers USING ( borrowernumber )
WHERE  1
    };

    my @params;

    if ( $fromDate && $toDate ) {
	$fromDate .= " 00:00:00";
	$toDate .= " 23:59:59";
    	$query .= qq{ AND a.date BETWEEN ? AND ? };
    	push( @params, $fromDate );
    	push( @params, $toDate );
    } elsif ( $fromDate ) {
	$fromDate .= " 00:00:00";
        $query .= qq{ AND a.date BETWEEN ? AND CURDATE() };
        push( @params, $fromDate );
    } else {
     	$query .= qq{ AND a.date < NOW() };
    }
    

    #    if ( $days_from && $days_to ) {
    #    $query .= qq{ AND a.date BETWEEN DATE_SUB(CURDATE(), INTERVAL ? DAY) AND DATE_SUB(CURDATE(), INTERVAL ? DAY) };
    #    push( @params, $days_from );
    #    push( @params, $days_to );
    #} else {
    #    $query .= qq{ AND a.date < NOW() };
    #}

    if ( $branchcode && $filter_issues ) {
        $query .= qq{ AND items.$branchcode_field = ? };
        push( @params, $branchcode );
    }

    if (@categorycodes) {
        $query .= qq{ AND borrowers.categorycode IN ( $categorycodes ) };
    } elsif ($default_patron_types) {
        $query .= qq{ AND borrowers.categorycode IN ( $default_patron_types ) };
    }

    if ( $patron_id ) {
        $query .= qq{ AND borrowers.borrowernumber = ? };
        push( @params, $patron_id );
    }
    elsif ( $patron_cardnumber ) {
        $query .= qq{ AND borrowers.cardnumber = ? };
        push( @params, $patron_cardnumber );
    }


    if ( @loststatuses ) {
        $query .= qq{ AND items.itemlost NOT IN ( $loststatuses ) };
    }

    #$query .= qq{ GROUP BY issues.issue_id };

    if ( $fines_from && $fines_to ) {
	    #$query .= qq{ HAVING SUM(a.amountoutstanding) >= ? AND SUM(a.amountoutstanding) <= ? };
	    $query .= qq{ AND a.amountoutstanding >= ? AND a.amountoutstanding) <= ? };
        push( @params, $fines_from, $fines_to );
    } elsif ( $fines_from ) {
	    #$query .= qq{ HAVING SUM(a.amountoutstanding) >= ?};
	$query .= qq{ AND a.amountoutstanding) >= ?};
        push( @params, $fines_from );
    } elsif ( $fines_to ) {
	    #$query .= qq{ AND a.amountoutstanding) <= ?};
	$query .= qq{ AND a.amountoutstanding > 0 AND a.amountoutstanding) <= ?};
        push( @params, $fines_to );
    } else {
	$query .= qq{ AND a.amountoutstanding > 0 };
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
    # print '<div><class="noprint"><pre>' . $query . '</pre></div>';
    print $template->output();
}

1;
