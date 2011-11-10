#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use Moonpig::Context::Test -all, '$Context';

with(
  'Moonpig::Test::Role::UsesStorage',
);

use Moonpig::Test::Factory qw(do_with_test_ledger);
use t::lib::Logger '$Logger';

use t::lib::TestEnv;

use Data::Dumper qw(Dumper);
use Data::GUID qw(guid_string);
use Path::Class;

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "store and retrieve" => sub {
  my ($self) = @_;

  my $pid = fork;
  Carp::croak("error forking") unless defined $pid;

  my $xid = 'yoyodyne:account:' . guid_string;

  if ($pid) {
    wait;
    if ($?) {
      my %waitpid = (
        status => $?,
        exit   => $? >> 8,
        signal => $? & 127,
        core   => $? & 128,
      );
      die("error with child: " . Dumper(\%waitpid));
    }
  } else {
    do_with_test_ledger({consumer => { template => 'demo-service', xid => $xid }}, sub {
      my ($ledger) = @_;
      $ledger->save;
    });
    exit(0);
  }

  my @guids = Moonpig->env->storage->ledger_guids;

  is(@guids, 1, "we have stored one guid");

  Moonpig->env->storage->
    do_with_ledger($guids[0], sub {
                     my $consumer = $_[0]->active_consumer_for_xid($xid);
                   }, { ro => 1 });

  # diag explain $retr_ledger;
  pass('we lived');
};

test "job queue" => sub {
  my ($self) = @_;

  do_with_test_ledger({}, sub {
    my ($ledger) = @_;

    $ledger->queue_job('test.job.a' => {
      foo => $^T,
      bar => 'serious business',
    });

    $ledger->queue_job('test.job.b' => {
      proc => $$,
      bar  => "..!",
    });
  });

  my @jobs_done;
  Moonpig->env->storage->iterate_jobs('test.job.a' => sub {
    my ($job) = @_;
    isa_ok($job, 'Moonpig::Job');
    is($job->job_id, 1, "cheating: we know we number jobs from 1");
    is_deeply(
      $job->payloads,
      {
        foo => $^T,
        bar => 'serious business',
      },
      "payloads as expected",
    );
    push @jobs_done, $job->job_id;

    Moonpig->env->storage->iterate_jobs('test.job.a' => sub {
      my ($job) = @_;
      push @jobs_done, $job->job_id;
      $job->mark_complete;
    });

    $job->mark_complete;
  });

  Moonpig->env->storage->iterate_jobs('test.job.b' => sub {
    my ($job) = @_;
    isa_ok($job, 'Moonpig::Job');
    is($job->job_id, 2, "cheating: we know we number jobs from 1");
    is_deeply(
      $job->payloads,
      {
        proc => $$,
        bar  => '..!',
      },
      "payloads as expected",
    );
    push @jobs_done, $job->job_id;

    Moonpig->env->storage->iterate_jobs('test.job.b' => sub {
      my ($job) = @_;
      push @jobs_done, $job->job_id;
      $job->mark_complete;
    });

    $job->mark_complete;
  });

  Moonpig->env->storage->iterate_jobs('test.job.b' => sub {
    my ($job) = @_;
    push @jobs_done, $job->job_id;
    $job->mark_complete;
  });

  is_deeply(\@jobs_done, [ 1, 2 ], "completed jobs are completed");
};

test "job lock and unlock" => sub {
  my ($self) = @_;

  do_with_test_ledger({}, sub {
    my ($ledger) = @_;

    $ledger->queue_job('test.job' => {
      foo => $^T,
      bar => 'serious business',
    });
  });

  my $message = "I got handled by a stupid no-op handler.";

  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->storage->iterate_jobs('test.job' => sub {
      my ($job) = @_;
      $job->log($message);
    });
  });

  my $ran = 0;
  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->storage->iterate_jobs('test.job' => sub {
      my ($job) = @_;
      $ran = 1;

      my $logs = $job->get_logs;

      is(@$logs, 1, "we have a log for this job");
      is($logs->[0]{message}, $message, "it's the right message");
    });
  });

  ok($ran, "the job was unlocked after the previous work");
};

run_me;
done_testing;
