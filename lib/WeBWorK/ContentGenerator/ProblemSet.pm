################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2003 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WeBWorK/ContentGenerator/ProblemSet.pm,v 1.57 2004/09/05 18:00:23 sh002i Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::ContentGenerator::ProblemSet;
use base qw(WeBWorK::ContentGenerator);

=head1 NAME

WeBWorK::ContentGenerator::ProblemSet - display an index of the problems in a 
problem set.

=cut

use strict;
use warnings;
use CGI qw(*ul *li);
use WeBWorK::PG;
use WeBWorK::Timing;
use WeBWorK::Utils qw(sortByName);

sub initialize {
	my ($self) = @_;
	my $r = $self->r;
	my $db = $r->db;
	my $urlpath = $r->urlpath;
	my $authz = $r->authz;
	
	my $setName = $urlpath->arg("setID");
	my $userName = $r->param("user");
	my $effectiveUserName = $r->param("effectiveUser");

	my $user            = $db->getUser($userName); # checked
	my $effectiveUser   = $db->getUser($effectiveUserName); # checked
	my $set             = $db->getMergedSet($effectiveUserName, $setName); # checked
	
	die "user $user (real user) not found."  unless $user;
	die "effective user $effectiveUserName  not found. One 'acts as' the effective user."  unless $effectiveUser;

	# FIXME: some day it would be nice to take out this code and consolidate the two checks

	# because of the database fix, we have to split our invalidSet check into two parts
	# First, if $set is undefined then $setName was never valid
	$self->{invalidSet} = not defined $set;
	return if $self->{invalidSet};
	
	# Database fix (in case of undefined published values)
	# this is only necessary because some people keep holding to ww1.9 which did not have a published field
	# make sure published is set to 0 or 1
	if ($set->published ne "0" and $set->published ne "1") {
		my $globalSet = $db->getGlobalSet($set->set_id);
		$globalSet->published("1");	# defaults to published
		$db->putGlobalSet($globalSet);
		$set = $db->getMergedSet($effectiveUserName, $set->set_id);
	}
	
	# Second, a set is invalid if it is still unpublished and the user does not have the right permissions
	$self->{invalidSet} = !($set->published || $authz->hasPermissions($userName, "view_unpublished_sets"));
	return if $self->{invalidSet};

	my $publishedText = ($set->published) ? "visible to students." : "hidden from students.";
	my $publishedClass = ($set->published) ? "Published" : "Unpublished";
	$self->addmessage(CGI::p("This set is " . CGI::font({class=>$publishedClass}, $publishedText))) if $authz->hasPermissions($userName, "view_unpublished_sets");

	$self->{userName}        = $userName;
	$self->{user}            = $user;
	$self->{effectiveUser}   = $effectiveUser;
	$self->{set}             = $set;
	
	##### permissions #####
	
	$self->{isOpen} = time >= $set->open_date || $authz->hasPermissions($userName, "view_unopened_sets");
}

sub nav {
	my ($self, $args) = @_;
	my $r = $self->r;
	my $urlpath = $r->urlpath;

	my $courseID = $urlpath->arg("courseID");
	#my $problemSetsPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::ProblemSets", courseID => $courseID);
	my $problemSetsPage = $urlpath->parent;
	
	my @links = ("Problem Sets" , $r->location . $problemSetsPage->path, "navUp");
	return $self->navMacro($args, "", @links);
}

sub siblings {
	my ($self) = @_;
	my $r = $self->r;
	my $db = $r->db;
	my $authz = $r->authz;
	my $urlpath = $r->urlpath;
	
	
	my $courseID = $urlpath->arg("courseID");
	my $user = $r->param('user');
	my $eUserID = $r->param("effectiveUser");
	my @setIDs = sortByName(undef, $db->listUserSets($eUserID));
	# do not show unpublished siblings unless user is allowed to view unpublished sets
	unless ($authz->hasPermissions($user, "view_unpublished_sets") ) {
		@setIDs    = grep {my $visible = $db->getGlobalSet( $_)->published; (defined($visible))? $visible : 1} 
	                     @setIDs;
	}
	print CGI::start_ul({class=>"LinksMenu"});
	print CGI::start_li();
	print CGI::span({style=>"font-size:larger"}, "Problem Sets");
	print CGI::start_ul();

	# FIXME: setIDs contain no info on published/unpublished so unpublished sets are still printed
	$WeBWorK::timer->continue("Begin printing sets from listUserSets()") if defined $WeBWorK::timer;
	foreach my $setID (@setIDs) {
		my $setPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::ProblemSet",
			courseID => $courseID, setID => $setID);
		print CGI::li(CGI::a({href=>$self->systemLink($setPage)}, $setID)) ;
	}
	$WeBWorK::timer->continue("End printing sets from listUserSets()") if defined $WeBWorK::timer;

	# FIXME: when database calls are faster, this will get rid of unpublished sibling links
	#$WeBWorK::timer->continue("Begin printing sets from getMergedSets()") if defined $WeBWorK::timer;	
	#my @userSetIDs = map {[$eUserID, $_]} @setIDs;
	#my @sets = $db->getMergedSets(@userSetIDs);
	#foreach my $set (@sets) {
	#	my $setPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::ProblemSet", courseID => $courseID, setID => $set->set_id);
	#	print CGI::li(CGI::a({href=>$self->systemLink($setPage)}, $set->set_id)) unless !(defined $set && ($set->published || $authz->hasPermissions($user, "view_unpublished_sets"));
	#}
	#$WeBWorK::timer->continue("Begin printing sets from getMergedSets()") if defined $WeBWorK::timer;
	
	print CGI::end_ul();
	print CGI::end_li();
	print CGI::end_ul();
	
	return "";
}

sub info {
	my ($self) = @_;
	my $r = $self->r;
	my $ce = $r->ce;
	my $db = $r->db;
	my $authz = $r->authz;
	my $urlpath = $r->urlpath;
	
	return "" unless $self->{isOpen};
	
	my $courseID = $urlpath->arg("courseID");
	my $setID = $r->urlpath->arg("setID");

	my $userID = $r->param("user");
	my $eUserID = $r->param("effectiveUser");
	
	my $effectiveUser = $db->getUser($eUserID); # checked 
	my $set  = $db->getMergedSet($eUserID, $setID); # checked
	
	die "effective user $eUserID not found. One 'acts as' the effective user." unless $effectiveUser;
	# FIXME: this was already caught in initialize()
	die "set $setID for effectiveUser $eUserID not found." unless $set;
	
	my $psvn = $set->psvn();
	
	my $screenSetHeader = $set->set_header || $ce->{webworkFiles}->{screenSnippets}->{setHeader};
	my $displayMode     = $ce->{pg}->{options}->{displayMode};
	
	if (defined $r->param("editMode") and $r->param("editMode") eq "temporaryFile") {
		$screenSetHeader = "$screenSetHeader.$userID.tmp";
		$displayMode = $r->param("displayMode") if $r->param("displayMode");
	}
	
	return "" unless defined $screenSetHeader and $screenSetHeader;
	
	# decide what to do about problem number
	my $problem = WeBWorK::DB::Record::UserProblem->new(
		problem_id => 0,
		set_id => $set->set_id,
		login_id => $effectiveUser->user_id,
		source_file => $screenSetHeader,
		# the rest of Problem's fields are not needed, i think
	);
	
	my $pg = WeBWorK::PG->new(
		$ce,
		$effectiveUser,
		$r->param('key'),
		$set,
		$problem,
		$psvn,
		{}, # no form fields!
		{ # translation options
			displayMode     => $displayMode,
			showHints       => 0,
			showSolutions   => 0,
			processAnswers  => 0,
		},
	);
	
	if (defined($set) and $set->set_header and $authz->hasPermissions($userID, "modify_problem_sets")) {  
		#FIXME ?  can't edit the default set header this way
		my $editorPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::PGProblemEditor",
			courseID => $courseID, setID => $set->set_id, problemID => 0);
		my $editorURL = $self->systemLink($editorPage);
		
		print CGI::p(CGI::b("Set Info"), " ",
			CGI::a({href=>$editorURL}, "[edit]"));
	} else {
		print CGI::p(CGI::b("Set Info"));
	}
	
	if ($pg->{flags}->{error_flag}) {
		print CGI::div({class=>"ResultsWithError"}, $self->errorOutput($pg->{errors}, $pg->{body_text}));
	} else {
		print $pg->{body_text};
	}
	
	return "";
}

sub body {
	my ($self) = @_;
	my $r = $self->r;
	my $ce = $r->ce;
	my $db = $r->db;
	my $urlpath = $r->urlpath;

	my $courseID = $urlpath->arg("courseID");
	my $setName = $urlpath->arg("setID");
	my $effectiveUser = $r->param('effectiveUser');

	my $set = $db->getMergedSet($effectiveUser, $setName);  # checked
	# FIXME: this was already caught in initialize()
	# die "set $setName for user $effectiveUser not found" unless $set;

	if ($self->{invalidSet}) {
		return CGI::div({class=>"ResultsWithError"},
			CGI::p("The selected problem set ($setName) is not a valid set for $effectiveUser."));
	}
	
	unless ($self->{isOpen}) {
		return CGI::div({class=>"ResultsWithError"},
			CGI::p("This problem set is not available because it is not yet open."));
	}
	
	#my $hardcopyURL =
	#	$ce->{webworkURLs}->{root} . "/"
	#	. $ce->{courseName} . "/"
	#	. "hardcopy/$setName/?" . $self->url_authen_args;
	
	my $hardcopyPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Hardcopy",
		courseID => $courseID, setID => $setName);
	my $hardcopyURL = $self->systemLink($hardcopyPage);
	
	print CGI::p(CGI::a({href=>$hardcopyURL}, "Download a hardcopy of this problem set."));
	
	print CGI::start_table();
	print CGI::Tr(
		CGI::th("Name"),
		CGI::th("Attempts"),
		CGI::th("Remaining"),
		CGI::th("Status"),
	);
	
	my @problemNumbers = $db->listUserProblems($effectiveUser, $setName);
	foreach my $problemNumber (sort { $a <=> $b } @problemNumbers) {
		my $problem = $db->getMergedProblem($effectiveUser, $setName, $problemNumber); # checked
		die "problem $problemNumber in set $setName for user $effectiveUser not found." unless $problem;
		print $self->problemListRow($set, $problem);
	}
	
	print CGI::end_table();
	
	## feedback form
	#my $ce = $self->{ce};
	#my $root = $ce->{webworkURLs}->{root};
	#my $courseName = $ce->{courseName};
	#my $feedbackURL = "$root/$courseName/feedback/";
	#print
	#	CGI::start_form(-method=>"POST", -action=>$feedbackURL),"\n",
	#	$self->hidden_authen_fields,"\n",
	#	CGI::hidden("module",             __PACKAGE__),"\n",
	#	CGI::hidden("set",                $self->{set}->set_id),"\n",
	#	CGI::hidden("problem",            ""),"\n",
	#	CGI::hidden("displayMode",        $self->{displayMode}),"\n",
	#	CGI::hidden("showOldAnswers",     ''),"\n",
	#	CGI::hidden("showCorrectAnswers", ''),"\n",
	#	CGI::hidden("showHints",          ''),"\n",
	#	CGI::hidden("showSolutions",      ''),"\n",
	#	CGI::p({-align=>"left"},
	#		CGI::submit(-name=>"feedbackForm", -label=>"Email instructor")
	#	),
	#	CGI::endform(),"\n";
	
	# feedback form url
	my $feedbackPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Feedback",
		courseID => $courseID);
	my $feedbackURL = $self->systemLink($feedbackPage, authen => 0); # no authen info for form action
	
	#print feedback form
	print
		CGI::start_form(-method=>"POST", -action=>$feedbackURL),"\n",
		$self->hidden_authen_fields,"\n",
		CGI::hidden("module",             __PACKAGE__),"\n",
		CGI::hidden("set",                $self->{set}->set_id),"\n",
		CGI::hidden("problem",            ''),"\n",
		CGI::hidden("displayMode",        $self->{displayMode}),"\n",
		CGI::hidden("showOldAnswers",     ''),"\n",
		CGI::hidden("showCorrectAnswers", ''),"\n",
		CGI::hidden("showHints",          ''),"\n",
		CGI::hidden("showSolutions",      ''),"\n",
		CGI::p({-align=>"left"},
			CGI::submit(-name=>"feedbackForm", -label=>"Email instructor")
		),
		CGI::endform(),"\n";
	
	return "";
}

sub problemListRow($$$) {
	my ($self, $set, $problem) = @_;
	my $r = $self->r;
	my $urlpath = $r->urlpath;
	
	my $courseID = $urlpath->arg("courseID");
	my $setID = $set->set_id;
	my $problemID = $problem->problem_id;
	
	my $interactiveURL = $self->systemLink(
		$urlpath->newFromModule("WeBWorK::ContentGenerator::Problem",
			courseID => $courseID, setID => $setID, problemID => $problemID)
	);
	
	my $interactive = CGI::a({-href=>$interactiveURL}, "Problem $problemID");
	my $attempts = $problem->num_correct + $problem->num_incorrect;
	my $remaining = $problem->max_attempts < 0
		? "unlimited"
		: $problem->max_attempts - $attempts;
	my $rawStatus = $problem->status || 0;
	my $status;
	$status = eval{ sprintf("%.0f%%", $rawStatus * 100)}; # round to whole number
	$status = 'unknown(FIXME)' if $@; # use a blank if problem status was not defined or not numeric.
	                                  # FIXME  -- this may not cover all cases.
	
	my $msg = ($problem->value) ? "" : "(This problem will not count towards your grade.)";
	
	return CGI::Tr(CGI::td({-nowrap=>1, -align=>"center"}, [
		$interactive,
		$attempts,
		$remaining,
		$status . " " . $msg,
	]));
}

1;
