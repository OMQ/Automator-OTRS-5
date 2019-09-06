# VERSION:1.1
# --
# Kernel/Config/Files/ZZZOmqAutomatorRepository.pm - Add online package repository
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

package Kernel::Config::Files::ZZZOmqAutomatorRepository;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub Load {
    my ($File, $Self) = @_;

    my $RepositoryList = $Self->{'Package::RepositoryList'};
    if (!IsHashRefWithData($RepositoryList)) {
        $RepositoryList = {};
    }

    # base url of otrs packages
    my $RepositoryBase = 'https://s3.eu-central-1.amazonaws.com/omq-otrs-packages/';

    # remove all omq related repositories, otherwise
    # multiple repositories might get added (dev, public...)
    REPOSITORYURL:
    for my $RepositoryURL (sort keys %{$RepositoryList}) {
        next REPOSITORYURL if $RepositoryURL !~ m{\A$RepositoryBase};
        delete $RepositoryList->{$RepositoryURL};
    }

    my $RepositoryName = 'otrs-5';

    # specify branch (develop|public)
    my $RepositoryBranch = 'develop';

    # build url
    my $RepositoryURL = $RepositoryBase . $RepositoryName . '/' . $RepositoryBranch;

    # add public repository
    $RepositoryList->{ $RepositoryURL } = 'OMQ repository (' . $RepositoryBranch . ')';

    # set temporary config entry
    $Self->{'Package::RepositoryList'} = $RepositoryList;

    return 1;
}


# disable redefine warnings in this scope
{
    # nofilter(TidyAll::Plugin::OTRS::Perl::PerlCritic)
    no warnings 'redefine';

    sub Kernel::System::CloudService::Backend::Run::new {
        my ( $Type, %Param ) = @_;

        # allocate new hash for object
        my $Self = {};
        bless($Self, $Type);

        # set system registration data
        %{ $Self->{RegistrationData} } =
            $Kernel::OM->Get('Kernel::System::SystemData')->SystemDataGroupGet(
                Group  => 'Registration',
                UserID => 1,
            );

        $Self->{CloudServiceURL} = 'https://cloud.otrs.com/otrs/public.pl';
        return $Self;
    }

}

1;