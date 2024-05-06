#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper qw/Dumper/;

open(my $fh, "< $ARGV[0]") or die "can't open: $@";
my $offset = $ARGV[1] || -1;

my $test = '';
my %stats = ();
my %stats_count = ();
my %timers = ();
my $main_test = '';
my $next_test = '';

my @tests = ();

my $cur_test = '';
my $cur_st = '';
while (my $line = <$fh>) {
    # We parse one test at a time.
    # Retrieve and initialize all values we need as soon as we find
    # it started.
    #
    # If FULLSTATS, we don't want it to skew results
    # cmd_get / cmd_set, for example
    if ($line =~ m/^.*FULLSTATS/) {
	last;
    }

    if ($line =~ m/^.*START \| (.*)/) {
        $cur_test = {name => $1, st => []};
        push(@tests, $cur_test);
        $cur_st = {name => $1, stats => {}, statsc => {}, timers => {}};
        push(@{$cur_test->{st}}, $cur_st);
    # We are interested in cmd_[get|set] only.
    } elsif ($line =~ m/^.*\| STAT \| (cmd_\S+) \| (\d+)/) {
        my $s = $1;
        my $n = $2;

	$cur_st->{stats}->{$s} += $n;
	$cur_st->{statsc}->{$s}++;
    } 
}    
# Reset handle, and read it again. But now only parse TIMER entries
seek($fh, 0, 0);

while (my $line = <$fh>) {
    if ($line =~ m/^.* \| TIMER \| (\S+)/) {
        parse_timers($1, $cur_st->{timers}, $fh);
    }
}

for my $t (@tests) {
    print("======= TEST ", $t->{name}, " =======\n");
    if ($offset != -1) {
        my $st = $t->{st}->[$offset];
        display_test($st);
    } else {
        for my $st (@{$t->{st}}) {
            display_test($st);
        }
    }
}

#print Dumper(\@tests), "\n";

print("done\n");

sub display_test {
    my $st = shift;
    print("--- subtest ", $st->{name}, " ---\n");
    for my $key (sort keys %{$st->{stats}}) {
        print("stat: $key : \n");
	print(" Total Ops: ", $st->{stats}->{$key}, "\n");
	print(" Rate: ", int($st->{stats}->{$key} / $st->{statsc}->{$key}), "/s \n");
    }
    for my $cmd (sort keys %{$st->{timers}}) {
        my $s = $st->{timers}->{$cmd};
        my $us = $s->{us};
        my $ms = $s->{ms};

        # total the counts.
        my $sum = 0;
        for (0..2) {
            $sum += $us->[$_];
        }
        for my $n (@{$ms}) {
            $sum += $n if defined $n;
        }
        $sum += $s->{oob};

        print("=== timer $cmd ===\n");
        printf "1us\t%d\t%.3f%%\n", $us->[0], $us->[0] / $sum * 100;
        printf "10us\t%d\t%.3f%%\n", $us->[1], $us->[1] / $sum * 100;
        printf "100us\t%d\t%.3f%%\n", $us->[2], $us->[2] / $sum * 100;

        for (1..100) {
            if (defined $ms->[$_]) {
                printf "%dms\t%d\t%.5f%%\n", $_, $ms->[$_], $ms->[$_] / $sum * 100;
            }
        }
        if ($s->{oob}) {
            printf "100ms+\t%d\t%.5f%%\n", $s->{oob}, $s->{oob} / $sum * 100;
        }
    }
}

sub parse_timers {
    my $n = shift;
    my $h = shift;
    my $fh = shift;
    if (! defined $h->{$n}) {
        $h->{$n} = { us => [0, 0, 0], ms => [], oob => 0 };
    }
    my $s = $h->{$n};

    while (my $line = <$fh>) {
        if ($line =~ m/.*\| FULLSTATS$/) {
            last;
        }
	# This condition is important to ensure we parse mixed tests,
	# and add timers to their respective buckets
        if ($line =~ m/.*\| ENDTIMER$/) {
	    return;
    	}
        if ($line =~ m/\| TIME \| (\d+)us \| (\d+)/) {
            my $b = $1;
            my $cnt = $2;
            if ($b eq "1") { $s->{us}->[0] += $cnt }
            if ($b eq "10") { $s->{us}->[1] += $cnt }
            if ($b eq "100") { $s->{us}->[2] += $cnt }
        } elsif ($line =~ m/\| TIME \| (\d+)ms \| (\d+)/) {
            $s->{ms}->[$1] += $2;
        } elsif ($line =~ m/\| TIME \| 100ms\+: \| (\d+)/) {
            $s->{oob} += $1;
        }
    }
}
