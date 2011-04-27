package Moonpig::App::Ob::Commands;
use strict;
use warnings;
use Moonpig::Util qw(class);

sub exit { warn "bye\n"; exit 0 }

sub dump {
  my ($args) = @_;
  my @extra;
  if ($args->eval_ok) {
    my $val = my $s = $args->value;
    if ($args->primary =~ /^(dump|x)$/) {
      require Data::Dumper;
      # callback to use actual value, not string, as $it
      @extra = (sub { $args->hub->last_result($val) });
      $s = Data::Dumper::Dumper($val);
    }
    return ($s, @extra);
  } else {
    warn $args->exception;
    return;
  }
}

sub help {
  my ($args) = @_;
  my $tab = $args->hub->command_table;
  my $rtab = {};
  while (my ($cname, $code) = each %$tab) {
    push @{$rtab->{$code}}, $cname;
  }
  my @res;
  for my $aliases (values %$rtab) {
    warn " > $aliases = (@$aliases)\n";
    my @words = sort @$aliases;
    if (@words> 1) {
      push @res, $words[0] . " (" . join(", ", @words[1..$#words]) . ")";
    } else {
      push @res, $words[0];
    }
  }
  return join "\n", sort(@res), "";
}

sub reload {
  warn "reloading $0...\n";
  exec $0, @ARGV;
  die "exec $0: $!";
}

sub shell {
  my ($args) = @_;
  my @cmd = @{$args->arg_list};

  if (! @cmd) {
    my $shell = $ENV{SHELL} || (-x '/bin/bash' ? '/bin/bash' : '/bin/sh');
    warn "Use 'exit' to return from shell\n";
    my $rc = system $shell;
    $rc == 0 or warn "shell failed\n";
    return;
  }

  my $res = readpipe (join " ", @cmd);
  my $status = $? >> 8;
  my $sig = $? & 255;
  if ($sig) {
    warn "command died with signal $sig\n";
  } elsif ($status) {
    warn "command exited with non-zero status $status\n";
  }
  return $res;
}

sub store {
  my ($args) = @_;
  my @argl = $args->list_value;
  unless (@argl) {
    warn "Usage: store ledger...\n";
    return "";
  }
  $args->hub->storage->_store_ledger($_) for @argl;
}

sub generate {
  my ($args) = @_;
  my ($subcommand) = $args->arg_list->[0] || 'help';
  if ($subcommand eq 'ledger') {
    return class('Ledger')->new({ contact => _gen_contact() });
  } elsif ($subcommand eq 'contact') {
    return _gen_contact();
  } else {
    my $me = $args->primary;
    warn "Usage: $me [ledger|contact]\n";
    return "";
  }
}

{
  my $N = 'a';
  sub _gen_contact {
    my $name = "\U$N\E Jones";
    my $email = qq{$N\@example.com};
    $N++;
    return class('Contact')->new({ name => $name,
                                   email_addresses => [ $email ],
                                 });
  }
}

1;
