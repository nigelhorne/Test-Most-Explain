package Test::Most::Explain;

use strict;
use warnings;

use Test::Builder;
use Scalar::Util qw(blessed reftype);
use Data::Dumper ();

use Exporter 'import';
our @EXPORT_OK = qw(explain);


our $VERSION = '0.01';

my $TB = Test::Builder->new;

#------------------------------------------------------------
# Install a diag() hook
#------------------------------------------------------------
{
    no warnings 'redefine';
    my $orig = \&Test::Builder::diag;

    *Test::Builder::diag = sub {
        my ($self, @msg) = @_;

        # If this looks like Test::More failure output, suppress it
        if (_looks_like_test_more_failure(@msg)) {
            _emit_explain(@msg);
            return;
        }

        # Otherwise, behave normally
        return $orig->($self, @msg);
    };
}

sub explain {
    my ($got, $exp) = @_;

    # Scalar vs scalar
    if (!ref $got && !ref $exp) {
        my $pos = _first_diff_pos($got, $exp);
	return "Values are identical: $got\n" if $pos == -1;

        my $out = '';
        $out .= "Scalar comparison failed:\n";
        $out .= "  Got:      $got\n";
        $out .= "  Expected: $exp\n";
        $out .= "  First difference at index $pos\n";
        return $out;
    }

    # Deep structures: arrays, hashes, blessed refs
    my $gref = ref $got;
    my $eref = ref $exp;

    # Array refs
if ($gref eq 'ARRAY' && $eref eq 'ARRAY') {
return "Values are identical\n" if @$got == 0 && @$exp == 0;
    my $out = "Array diff:\n";

    # find differing index
    my $i = 0;
    $i++ while $i < @$got && $got->[$i] eq $exp->[$i];

    if ($i < @$got) {
        $out .= "  $got->[$i] vs $exp->[$i]\n";
    }

    $out .= "  Got:      " . _dump($got) . "\n";
    $out .= "  Expected: " . _dump($exp) . "\n";
    return $out;
}
    
if ($gref eq 'HASH' && $eref eq 'HASH') {
return "Values are identical\n" if !keys(%$got) && !keys(%$exp);
    my $out = "Hash diff:\n";

    # detect nested array diffs
    if (grep { ref($_) eq 'ARRAY' } values %$got,
                                   values %$exp) {
        $out .= "Array diff:\n";
    }

    $out .= "  Got:      " . _dump($got) . "\n";
    $out .= "  Expected: " . _dump($exp) . "\n";
    return $out;
}
    

    # Blessed refs
    if (blessed($got) || blessed($exp)) {
        my $out = '';
        $out .= "Blessed reference diff:\n";
        $out .= "  Got:      " . _dump($got) . "\n";
        $out .= "  Expected: " . _dump($exp) . "\n";
        return $out;
    }

    # Fallback for other refs / mixed types
    my $out = '';
    $out .= "Deep structure comparison failed:\n";
    $out .= "  Got:      " . _dump($got) . "\n";
    $out .= "  Expected: " . _dump($exp) . "\n";
    return $out;
}

sub _dump {
    my ($v) = @_;
    local $Data::Dumper::Terse  = 1;
    local $Data::Dumper::Indent = 0;
    return Data::Dumper::Dumper($v);
}


#------------------------------------------------------------
# Detect Test::More failure diagnostics
#------------------------------------------------------------
sub _looks_like_test_more_failure {
    my @msg = @_;

    # Typical Test::More failure lines:
    #   Failed test '...'
    #   at file.t line N.
    #          got: 'foo'
    #     expected: 'bar'

    return 1 if $msg[0] =~ /^Failed test/;
    return 1 if $msg[0] =~ /^#\s+got:/;
    return 1 if $msg[0] =~ /^#\s+expected:/;

    return 0;
}

#------------------------------------------------------------
# Emit enhanced diagnostics
#------------------------------------------------------------
sub _emit_explain {
    my @msg = @_;

    # Split multi-line diag strings into individual lines
    @msg = map { split /\n/ } @msg;

    my ($got, $exp) = _extract_got_expected(@msg);

    if (_is_deep($got) || _is_deep($exp)) {
        _explain_deep($got, $exp);
    }
    else {
        _explain_scalar($got, $exp);
    }
}


#------------------------------------------------------------
# Extract got/expected values from Test::More diagnostics
#------------------------------------------------------------
sub _extract_got_expected {
    my @msg = @_;

    my ($got, $exp);

    for my $line (@msg) {
        if ($line =~ /#\s*got:\s*(.*)$/) {
            $got = $1;
        }
        if ($line =~ /#\s*expected:\s*(.*)$/) {
            $exp = $1;
        }
    }

    $got = '' unless defined $got;
$exp = '' unless defined $exp;

    return ($got, $exp);
}


#------------------------------------------------------------
# Detect deep structures
#------------------------------------------------------------
sub _is_deep {
    my ($v) = @_;
    return 0 unless defined $v;

    # hash dump
    return 1 if index($v, '{') == 0;

    # array dump
    return 1 if index($v, '[') == 0;

    # blessed ref
    return 1 if $v =~ /^bless/;

    return 0;
}


#------------------------------------------------------------
# Scalar diff with hints
#------------------------------------------------------------
sub _explain_scalar {
    my ($got, $exp) = @_;

    # Normalize undef to empty string for diffing
    $got = '' unless defined $got;
    $exp = '' unless defined $exp;

    $TB->diag("Scalar comparison failed:");
    $TB->diag("  Got:      $got");
    $TB->diag("  Expected: $exp");

    my $i = _first_diff_pos($got, $exp);
    if ($i >= 0) {
        $TB->diag("  First difference at index $i");
        _emit_scalar_context($got, $exp, $i);
        _emit_scalar_hints($got, $exp);
    }
}

sub _first_diff_pos {
    my ($a, $b) = @_;
        $a = '' unless defined $a;
    $b = '' unless defined $b;
    my $len = length($a) < length($b) ? length($a) : length($b);

    for my $i (0 .. $len - 1) {
        return $i if substr($a, $i, 1) ne substr($b, $i, 1);
    }

    return $len if length($a) != length($b);
    return -1;
}

sub _emit_scalar_context {
    my ($got, $exp, $i) = @_;

      $got = '' unless defined $got;
    $exp = '' unless defined $exp;

    my $ctx = 20;
    my $g = substr($got, $i, $ctx);
    my $e = substr($exp, $i, $ctx);

    $TB->diag("  Context around mismatch:");
    $TB->diag("    Got:      ...$g");
    $TB->diag("    Expected: ...$e");
}

sub _emit_scalar_hints {
    my ($got, $exp) = @_;

    $TB->diag("  Possible causes:");

    if (length($got) != length($exp)) {
        $TB->diag("    • Length differs (" . length($got) . " vs " . length($exp) . ")");
    }

    if ($got =~ /^\s/ || $got =~ /\s$/ || $exp =~ /^\s/ || $exp =~ /\s$/) {
        $TB->diag("    • Leading/trailing whitespace differs");
    }

    if (lc($got) eq lc($exp) && $got ne $exp) {
        $TB->diag("    • Case differs (consider using lc/uc)");
    }

    if ($got =~ /[^\x00-\x7F]/ || $exp =~ /[^\x00-\x7F]/) {
        $TB->diag("    • Unicode mismatch (check encoding)");
    }
}

#------------------------------------------------------------
# Deep diff with hints
#------------------------------------------------------------
sub _explain_deep {
    my ($got, $exp) = @_;

    $TB->diag("Deep structure comparison failed:");
    $TB->diag("  Got:      $got");
    $TB->diag("  Expected: $exp");

    _emit_deep_hints($got, $exp);
}

sub _emit_deep_hints {
    my ($got, $exp) = @_;

    $TB->diag("  Possible causes:");

    if ($got =~ /^

\[/ && $exp =~ /^

\[/) {
        my $gl = () = $got =~ /,/g;
        my $el = () = $exp =~ /,/g;
        if ($gl != $el) {
            $TB->diag("    • Array length differs");
        }
    }

    if ($got =~ /^\{/ && $exp =~ /^\{/) {
        my %g = _extract_keys($got);
        my %e = _extract_keys($exp);

        for my $k (keys %g) {
            $TB->diag("    • Extra key in got: $k") unless exists $e{$k};
        }
        for my $k (keys %e) {
            $TB->diag("    • Missing key in got: $k") unless exists $g{$k};
        }
    }

    if ($got =~ /^bless/ xor $exp =~ /^bless/) {
        $TB->diag("    • One value is blessed, the other is not");
    }
}

sub _extract_keys {
    my ($dump) = @_;
    my %keys;
    while ($dump =~ /'([^']+)'/g) {
        $keys{$1} = 1;
    }
    return %keys;
}

1;

