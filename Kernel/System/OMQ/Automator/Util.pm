# --
# Kernel/System/OMQ/Automator/Util.pm - Util module for the automator
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# Extensions Copyright © 2010-2017 OMQ GmbH, http://www.omq.de
#
# written/edited by:
# * info(at)omq(dot)de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::OMQ::Automator::Util;

use strict;
use warnings;

#use Kernel::System::VariableCheck qw(:all);

use Kernel::System::OMQ::Automator::Constants;

use LWP::UserAgent;
use JSON;
use Encode qw(encode);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::OMQ::AutoResponder::Util - Util module for Auto responder.

=head1 SYNOPSIS

Contains some utilf functions

=cut

=over

=item new()

Constructor

=cut

sub new {
    my ($Type) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub SendRequest {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    my $Proxy         = $ConfigObject->Get('WebUserAgent::Proxy');
    my $SkipSSLVerify = $ConfigObject->Get('WebUserAgent::DisableSSLVerification');
    my $TimeOut       = $ConfigObject->Get('WebUserAgent::Timeout') || 30;

    my $BaseURL = $Self->GetBaseURL();
    if ( !$BaseURL || $BaseURL eq '' ) {
        return;
    }

    my $ApiKey = $Param{ApiKey};

    # check passed api key
    if ( !$ApiKey || $ApiKey eq '' ) {
        $ApiKey = $ConfigObject->Get('OMQ::Automator::Settings::Apikey');

        # if still empty, do not send request
        if ( !$ApiKey || $ApiKey eq '' ) {
            return;
        }
    }

    my $UserAgent = LWP::UserAgent->new();

    # add proxy settings of available
    if ($Proxy) {
        $UserAgent->proxy( [ 'http', 'https' ], $Proxy );
    }

    # skip ssl verify
    if ($SkipSSLVerify) {
        $UserAgent->ssl_opts(
            verify_hostname => 0,
        );
    }

    # set timeout
    $UserAgent->timeout($TimeOut);

    my $Request = HTTP::Request->new( $Param{Type} => $BaseURL . $Param{Url} );

    # set request header
    $Request->header(
        'Accept'               => 'application/json',
        'X-Omq-Tenant-Api-Key' => $ApiKey,
        'Content-Type'         => 'application/json'
    );

    if ( $Param{Body} ) {
        $Request->content( JSON->new()->utf8()->encode( $Param{Body} ) );
    }

    # send request
    my $Response = $UserAgent->request($Request);

    # do nothing if open tickets couldn't be loaded
    if ( !$Response->is_success() ) {
        my $ErrorMessage = "Could not send request to OMQ Backend.\n";
        $ErrorMessage .= "HTTP ERROR Url: " . $BaseURL . $Param{Url} . "\n";
        $ErrorMessage .= "HTTP ERROR Code: " . $Response->code() . "\n";
        $ErrorMessage .= "HTTP ERROR Message: " . $Response->message() . "\n";

        if ( $Response->decoded_content() ) {
            $ErrorMessage .= "HTTP ERROR Content: " . $Response->decoded_content() . "\n";
        }

        $LogObject->Log(
            Priority => 'error',
            Message  => $ErrorMessage
        );
        print "\n$ErrorMessage\n";

        return;
    }

    my $Content = $Response->decoded_content();
    if ( !$Content || $Content eq '' ) {
        return $Content;
    }

    # decode response
    return JSON->new()->utf8()->decode( encode( 'UTF-8', $Content ) );
}

sub GetUserID {
    my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');
    my $PostmasterUserID = $ConfigObject->Get('PostmasterUserID') || 1;
    my $UserID           = $PostmasterUserID;

    return $UserID;
}

=item GetBaseUrl()

Reads account from settings. Checks if account
is URL or account name. In case of account is a name,
the proper URL is returned.

=cut

sub GetBaseURL {
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Url          = $ConfigObject->Get('OMQ::Automator::Settings::URL');

    # if settings are empty, do nothing
    if ( !$Url || $Url eq '' ) {
        return;
    }

    # check if account is already url
    if ( $Url !~ "http://|https://" ) {
        $Url = "https://$Url.omq.de";
    }

    return $Url;
}

1;

=back
