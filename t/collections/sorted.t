#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use Moonpig::Env::Test;
use Moonpig::Util qw(class cents dollars);

use t::lib::Factory qw(build_ledger);

my ($Ledger, $Credit);

before run_test => sub {
  my ($self) = @_;

  $Ledger = build_ledger();
  $Credit = $Ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );
};

sub refund {
  my ($self, $amount) = @_;
  my $refund = $Ledger->add_refund(class('Refund'));
  $amount ||= dollars(1);
  $Ledger->create_transfer({
    type => 'credit_application',
    from => $Credit,
    to => $refund,
    amount => $amount,
  });
  return $refund;
}

test "refund collections" => sub {
  my ($self) = @_;

  my @r;
  for (4, 2, 8, 5, 7, 1) {
    $self->refund(cents($_ * 101));
  }

  my @refunds = $Ledger->refunds();
  is(@refunds, 6, "ledger loaded with five refunds");
  my $rc = $Ledger->refund_collection;

  is( exception { $rc->sort_key("amount") },
      undef,
      "set sort method name to 'amount'" );

  { my @all = $rc->all_sorted;
    is_deeply([ map $_->amount, @all ],
              [ map dollars($_), 1.01, 2.02, 4.04, 5.05, 7.07, 8.08 ],
              '->all_sorted');
  }

  is($rc->first->amount, dollars(1.01), "->first is least");
  is($rc->last ->amount, dollars(8.08), "->last is most");
};

test "miscellaneous tests" => sub {
  my ($self) = @_;
  my $cc = $Ledger->consumer_collection;

  like( exception { $cc->all_sorted },
        qr/no sort key defined/i,
        "no default sort key for consumers" );

 # Can't get TODO working with Tsst::Routine
 TODO: {
     local $TODO = "Can't check sort key method name without method_name_for type";
#     isnt( exception { $cc->sort_key("uglification") },
#           undef,
#           "correctly failed to set sort method name to something bogus" );
  }
};

run_me;
done_testing;
