#!/usr/bin/perl -w

# Treebank consistency checking
# Kaarel Kaljurand
# Sat May  1 16:15:11 EEST 2004

# TODO:
# * Allow only contiguous strings as groups (could be a commandline param)

use strict;
use Getopt::Long;

# Default values for commandline parameters

# What to index: word, pos, morph, edge
my $key = "word";

# What describes the index key: node, edge
my $value = "node";

# The nature of the context of the index key: word, pos, morph, edge
my $context = undef; # Will be defined later

my $lc = 0;
my $rc = 0;

# Undef in case you want the data unsorted
#my $skew = undef;
my $skew = 1;

my $help = "";
my $version = "";

my $getopt_result = GetOptions(
        "key=s"  	=> \$key,
        "value=s"  	=> \$value,
        "context=s"  	=> \$context,
        "lc=i" 		=> \$lc,
        "rc=i" 		=> \$rc,
        "skew" 		=> \$skew,
        "help"		=> \$help,
        "version"	=> \$version
);

if($version) { &show_version(); exit; }
if(!$getopt_result || $help) { &show_help(); exit; }

if($key ne "word" && $key ne "pos" && $key ne "edge" && $key ne "morph") {
        print STDERR "consitency.pl: fatal error: bad value for `key'\n";
        &show_help();
        exit;
}

if($value ne "node" && $value ne "edge") {
        print STDERR "consitency.pl: fatal error: bad value for `value'\n";
        &show_help();
        exit;
}

if(defined($context) && $context ne "word" && $context ne "pos" && $context ne "edge" && $context ne "morph") {
        print STDERR "consitency.pl: fatal error: bad value for `context'\n";
        &show_help();
        exit;
}

# Hash to hold a sentence in NEGRA table-format
my $h = {};

# Hash to hold the reorganized data
my $f = {};

my $sentstart = 0;
my $sentid = "";
my $linecount = 0;
my $ind = 0;

# Internally the pos column is really called "node"
if($key eq "pos") {
	$key = "node";
}

# If the commandline didn't specify the nature of the
# context, then it will be the same as the key.
if(!defined($context)) {
	$context = $key;
}

# Internally the pos column is really called "node"
if($context eq "pos") {
	$context = "node";
}


# Parse the input.
while(<STDIN>) {

	chomp;

	$linecount++;

	# If sentence starts, default the datastructure.
	if(/^#BOS/) {
		$sentstart = 1;
		$sentid = &get_sentence_id($_);
		$ind = 0;
		$h = {};
		next;
	}

	# If sentence ends, add the new groups to the index.
	if(/^#EOS/) {
		my $groups = &get_groups($h);
		my $flat_groups = &flat_groups($groups);

		# Just for debugging purposes
		#&print_groups($groups);
		#&print_groups($flat_groups);
		
		$f = &add_groups_to_index($f, $h, $flat_groups, $sentid, $ind);
		$sentstart = 0;
		next;
	}

	# If we are in the sentence
	if($sentstart) {

		my ($col1, $node, $morph, $edge, $parent) = split "\t+";

		if(!defined($parent)) {
			warn "Syntax error in corpus on line: $linecount\n";
			next;
		}

		# If a non-terminal node
		if($col1 =~ /^#/) {
			$col1 =~ s/^#//;
			$h->{$col1}->{"node"} = $node; 
			$h->{$col1}->{"morph"} = $morph; 
			$h->{$col1}->{"edge"} = $edge; 
			$h->{$col1}->{"parent"} = $parent; 
		}

		# If a terminal node (i.e. a word)
		else {
			$ind++;
			$h->{$ind}->{"word"} = $col1; 
			$h->{$ind}->{"node"} = $node; 
			$h->{$ind}->{"morph"} = $morph; 
			$h->{$ind}->{"edge"} = $edge; 
			$h->{$ind}->{"parent"} = $parent; 
		}
	}
}

if($skew) {
	$f = &add_skew_value($f);
	&print_data_with_skew($f);
}
else {
	&print_data($f);
}
exit;

###
# Program ends. Subroutines follow.
###

###
# Extract groups from the sentence.
###
sub get_groups
{
	my $h = shift;
	my $g = {};

	foreach my $i (keys %{$h}) {
		$g->{$h->{$i}->{"parent"}}->{$i} = 1;
	}

	return $g;
}

###
# Flat the groups, so that they would only contain terminals.
###
sub flat_groups
{
	my $g = shift;
	my $fg = {};

	foreach my $i (keys %{$g}) {
		my @terminals = &get_terminals($g, $i);
		$fg->{$i} = &list2hash(\@terminals);
	}

	return $fg;
}

###
# Recursively compile a list of terminals in a given group.
###
sub get_terminals
{
	my $g = shift;
	my $ind = shift;
	my @lnodes = ();

	foreach my $i (keys %{$g->{$ind}}) {
		if(defined $g->{$i}) {
			my @ln = &get_terminals($g, $i);
			push @lnodes, @ln;
		}
		else {
			# If a nonterminal does not have a corresponding
			# terminal.
			# BUG: This is not portable, since we use 500.
			if($i >= 500) {
				# This should never happen anyway,
				# or only if the input is buggy.
				# Should we report it here?
			}
			# Otherwise
			else {
				push @lnodes, $i;
			}
		}
	}

	return @lnodes;
}

###
# Output the groups. For debugging only.
###
sub print_groups
{
	my $g = shift;
	foreach my $i (keys %{$g}) {
		my @children = keys %{$g->{$i}};
		print "$i\t@children\n";
	}
}

###
# Get an id number that could be used to refer to the sentence in the
# treebank. Currently we extract it from the line that starts with
# "#BOS". We take the first number from it.
###
sub get_sentence_id
{
	my $bos_line = shift;

	my @sbos = split /\s+/, $bos_line;

	if(!defined($sbos[1])) {
		return "?";
	}
	else {
		return $sbos[1];
	}
}

###
# Add the new groups to the global index.
# Use actual words (edges, pos tags, ...) as the index key and
# group names (or edge names) as the index value.
###
sub add_groups_to_index
{
	my $f = shift;
	my $h = shift;
	my $groups = shift;
	my $sid = shift;
	my $slen = shift;

	foreach my $i (keys %{$groups}) {

		my $ks = &make_key_string($h, $groups->{$i}, $slen);

		# If the group is topmost (i.e. root)
		if($i == 0) {
			$f->{$ks}->{"ann"}->{"ROOT"}->{"count"}++;
			push @{$f->{$ks}->{"ann"}->{"ROOT"}->{"sid"}}, $sid;
		}
		# Otherwise
		else {
			$f->{$ks}->{"ann"}->{$h->{$i}->{$value}}->{"count"}++;
			push @{$f->{$ks}->{"ann"}->{$h->{$i}->{$value}}->{"sid"}}, $sid;
		}
	}

	return $f;
}

###
# The key in the index is going to be a sequence of words (or edge names, ...)
# that form a group. The key can be additionally have context words (or edge
# names, ...) for the left and right context. The amount of context
# is specified by commandline parameters.
###
sub make_key_string
{
	my $h = shift;
	my $g = shift;
	my $slen = shift;

	# Nucleus is the sequence without the context
	my @nucleus = sort {$a <=> $b} keys %{$g};
	my @key_string = @nucleus;

	# Add the left context
	for(	my $i = $nucleus[0] - 1;
		$i >= 1 && $i >= ($nucleus[0] - $lc);
		$i--) {
		unshift @key_string, $i;
	}

	# Add the right context
	for(	my $i = $nucleus[$#nucleus] + 1;
		$i <= $slen && $i <= $nucleus[$#nucleus] + $rc;
		$i++) {
		push @key_string, $i;
	}

	my @ks = ();

	foreach my $i (@key_string) {

		# If the word is in the nucleus, then put it into parentheses
		if(defined $g->{$i}) {
			push @ks, $h->{$i}->{$key};
		}
		# If the word is context word
		else {
			push @ks, "[" . $h->{$i}->{$context} . "]";
		}
	}

	my $ks = join "#", @ks;

	return $ks;
}

###
#  Convert a list to a hash by counting the occurances of the list members.
###
sub list2hash
{
	my $l = shift;
	my $h = {};

	foreach my $i (@{$l}) {
		$h->{$i}++;
	}

	return $h;
}

###
# Calculates the skew-value of a hash.
###
sub skew_value
{
	my $h = shift;

	my $sum = 0;
	my $count = 0;
	my $skew = 0;

	foreach my $i (keys %{$h}) {
		$sum = $sum + $h->{$i};
		$count++;
	}

	if($count == 1) {
		return -1;
	}

	# Count will always be > 0
	my $mean = $sum / $count; 

	foreach my $i (keys %{$h}) {
		$skew = $skew + ($h->{$i} - $mean) ** 2;
	}

	return $skew;
}

###
# Just a wrapper...
###
sub calc_skew_value
{
	my $h = shift;
	my $newh = {};

	foreach my $i (keys %{$h}) {
		$newh->{$i} = $h->{$i}->{"count"};
	}

	my $skew = &skew_value($newh);
	return $skew;
}

###
# Add the skew value to all the members of the index
###
sub add_skew_value
{
	my $f = shift;

	foreach my $i (keys %{$f}) {

		my $skew = &calc_skew_value($f->{$i}->{"ann"});
		$f->{$i}->{"skew"} = $skew;
	}

	return $f;
}

###
# Output the data
###
sub print_data
{
	my $f = shift;

	foreach my $i (keys %{$f}) {

		print "$i\n";

		&print_annotation($f->{$i}->{"ann"});
	}
}

###
# Output the data with skew values
###
sub print_data_with_skew
{
	my $f = shift;

	foreach my $i (sort {$f->{$b}->{"skew"} <=> $f->{$a}->{"skew"}} keys %{$f}) {

		print "$i\n";
		print "\t", $f->{$i}->{"skew"}, "\n";

		&print_annotation($f->{$i}->{"ann"});
	}
}

###
# Output the annotation
###
sub print_annotation
{
	my $ann = shift;

	# BUG: It's not so important to sort since we usually
	# have very little data here. Don't sort if
	# it takes too much time
	
	foreach my $j (sort {$ann->{$b}->{"count"} <=> $ann->{$a}->{"count"}} keys %{$ann}) {
		
		my $sids = join ",", @{$ann->{$j}->{"sid"}};

		print "\t\t", $ann->{$j}->{"count"}, "\t", $j, "\t", $sids, "\n";
	}
}

###
# Show version information
###
sub show_version
{
print <<EOF;
consistency.pl, ver 0.12
Sat May  1 16:15:04 EEST 2004
Kaarel Kaljurand (kaarel\@ut.ee)
EOF
}

###
# Show help
###
sub show_help
{
print <<EOF;
usage: consistency.pl OPTION...
OPTIONS:
        --key=[word|pos|edge|morph]	what to index (default: word)
        --value=[node|edge]		...and with what value (default: node)
        --context=[word|pos|edge|morph]	context's nature (default: same as key)
	--lc=[0|1|2|..]			amount of left context (default: 0)
	--rc=[0|1|2|..]			amount of right context (default: 0)
        --version			show version information
        --help				show this help message
EOF
}
