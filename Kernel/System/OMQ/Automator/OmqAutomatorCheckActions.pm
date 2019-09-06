# --
# Kernel/System/OMQ/Automator/OmqAutomatorCheckTasks.pm - Module to check automator tasks
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

package Kernel::System::OMQ::Automator::OmqAutomatorCheckActions;

use strict;
use warnings;

use JSON;
use MIME::Base64;

use Kernel::GenericInterface::Debugger;
use Kernel::GenericInterface::Operation::Ticket::TicketCreate;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::OMQ::Automator::Util',
    'Kernel::System::GenericAgent',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::GenericInterface::Debugger',
    'Kernel::System::GenericInterface::Webservice',
    'Kernel::GenericInterface::Operation::Ticket::TicketCreate'
);

=head1 NAME

Kernel::System::OMQ::Automator::AutomatorCheckTasks - Daemon Cron Task to check automator tasks.

=head1 SYNOPSIS

Called every 5 minutes by Daemon

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

=item Run()

Check open tasks on server. Delete after tasks have been executed.

=cut

sub Run {
    my ($Self) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    $LogObject->Log(
        Priority => 'notice',
        Message  => "OMQ automator: check actions.\n"
    );

    my $ApiKey = $ConfigObject->Get('OMQ::Automator::Settings::Apikey');
    $Self->CheckActionsForApiKey( ApiKey => $ApiKey );

    $LogObject->Log(
        Priority => 'notice',
        Message  => "OMQ automator: actions have been checked.\n"
    );

    return $Self;
}

=item CheckActionsForApiKey()

Load actions from server for passed api key.
Action format is json:

    {
      ticket_id: 379,
      job: {
        New: {
            "State": "open"
            "OwnerID": 1
        }
      }
    }

Delete all actions from server after execution.

=cut

sub CheckActionsForApiKey {
    my ( $Self, %Param ) = @_;

    my $OmqUtil = $Kernel::OM->Get('Kernel::System::OMQ::Automator::Util');
    my $ApiKey  = $Param{ApiKey};

    # get tasks from server
    my $Actions = $OmqUtil->SendRequest(
        Type   => 'GET',
        Url    => '/api/actions?execution_type=OTRS_GENERIC_AGENT',
        ApiKey => $ApiKey
    );

    # Loop through task, end execute each job
    for my $Action ( @{$Actions} ) {

        my $Content = JSON->new()->utf8()->decode( $Action->{content} );

        if ( $Content->{UseWebservice} ) {
            $Self->ExecuteWebservice( Data => $Content );
        }
        else {
            my $Job = $Content->{job};
            $Self->ExecuteJob(
                Job      => $Job,
                TicketID => $Content->{ticket_id}
            );
        }

        # mark as done executed tasks from server
        $OmqUtil->SendRequest(
            Type   => 'POST',
            Url    => '/api/actions/' . $Action->{id} . '/done',
            ApiKey => $ApiKey,
            Body   => {}
        );
    }

    return 1;
}

sub ExecuteWebservice {
    my ( $Self, %Param ) = @_;

    my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceGet(
        Name => "OMQ",
    );

    my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
        DebuggerConfig    => $Webservice->{Config}->{Debugger},
        WebserviceID      => $Webservice->{ID},
        CommunicationType => 'Provider',
        RemoteIP          => $ENV{REMOTE_ADDR},
    );

    my $Operation = Kernel::GenericInterface::Operation::Ticket::TicketCreate->new(
        WebserviceID   => $Webservice->{ID},
        DebuggerObject => $DebuggerObject
    );

    $Operation->Run( Data => $Param{Data} );
}

=item ExecuteJob()

Run generic agent for passed Job. Limit job execution on
passed ticket.

Possible Job Options:

    New: {
        SendNoNotification: 1 | 0, // default is 0
        Queue: "QueueName",
        QueueID: 3,
        Note: {
            Body: "", // if empty, no note will be created
            ArticleType: "note-internal",
            From: "GenericAgent",
            Subject: "Note",
        },

        State: "new",
        StateID: 1,

        PendingTime: ??,
        PendingTimeType: "",

        CustomerID: 1,
        CustomerUserLogin: "",

        Title: "",

        Type: "Unclassified",
        TypeID: 1,

        Service: "",
        ServiceID: 1,

        SLA: "",
        SLAID: 1,

        Priority: "",
        PriorityID: 1,

        Owner: "",
        OwnerID: "",

        Responsible: "",
        ResponsibleID: 1,

        Lock: "",
        LockID: 1,

        Module: "Name of module" // runs an otrs module, passed job object and ticket id
        ArchiveFlag: ""
        CMD: "" calls system command and passed ticket number and ticket id

        Delete: 1 // deletes ticket
    }

    Default note attributes (not changeable):

        SenderType      => 'agent',
        MimeType        => 'text/plain',
        Charset         => 'utf-8',
        UserID          => $Param{UserID},
        HistoryType     => 'AddNote',
        HistoryComment  => 'Generic Agent note added.',

=cut

sub ExecuteJob {
    my ( $Self, %Param ) = @_;

    # check params
    my $Job = $Param{Job};

    return if ( !$Job );

    my $TicketId = $Param{TicketID};
    if ( !$TicketId ) {
        $TicketId = $Self->CreateTicket();
    }

    # run job on generic agent
    my $GenericAgent = $Kernel::OM->Get('Kernel::System::GenericAgent');
    $GenericAgent->JobRun(
        Job => $Param{Name} || 'OMQ automator task',
        UserID       => 1,
        OnlyTicketID => $TicketId,
        Config       => $Job
    );

    # check for attachments
    if ( $Job->{New}->{Note}->{Attachment} ) {
        my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::Automator::Util');
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # get user id
        my $UserID = $OmqUtil->GetUserID();

        # get array of article ids
        my @Index = $TicketObject->ArticleIndex( TicketID => $TicketId );

        # return if empty
        return 1 if !@Index;

        # store each attachment to article
        for my $Attachment ( @{ $Job->{New}->{Note}->{Attachment} } ) {
            $TicketObject->ArticleWriteAttachment(
                Content     => decode_base64 $Attachment->{Content},
                ContentType => $Attachment->{ContentType},
                Filename    => $Attachment->{Filename},
                ArticleID   => $Index[-1],
                UserID      => $UserID,
            );
        }
    }

    return 1;
}

sub CreateTicket {
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::Automator::Util');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $UserID = $OmqUtil->GetUserID();

    my $TicketID = $TicketObject->TicketCreate(
        OwnerID  => $UserID,
        UserID   => $UserID,
        Queue    => 'Raw',
        State    => 'new',
        Lock     => 'unlock',
        Priority => '3 normal'
    );

    return $TicketID;
}

1;

=back
