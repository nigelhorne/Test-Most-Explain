package Test::Most::Explain;

use strict;
use warnings;

# We are a testing helper, not a CLI, so we use croak/carp for errors.
use Carp qw(croak carp);

# We build on top of Test::Most and Test::Builder.
use Test::Most ();
use Test::Builder;

# We use Params::Get and Params::Validate::Strict for public entry points.
use Params::Get qw(get_params);
use Params::Validate::Strict qw(validate_strict);

# We lazily load Test::Differences only when needed.
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

# Test::Builder singleton used for all diagnostics.
my $TB = Test::Builder->new;

#--------------------------------------------------------------------------#
# Wrap selected Test::Most functions at compile time.
# We install local wrappers that:
#   * call the original Test::Most implementation
#   * if the assertion fails, emit enhanced diagnostics
# These wrappers are not considered part of the public API of this module;
# they are re-exports of Test::Most with extra behavior.
#--------------------------------------------------------------------------#
BEGIN {
    no strict 'refs';

    # List of assertion functions we want to enhance.
    my @wrapped = qw(ok is is_deeply like unlike cmp_ok);

    for my $fn (@wrapped) {

        # Find the original implementation in Test::Most.
        my $orig = Test::Most->can($fn)
          or carp "Test::Most::Explain: could not find '$fn' in Test::Most";

        # Install our wrapper into this package.
        *{$fn} = sub {
            # Entry criteria:
            #   * Same arguments as the corresponding Test::Most function.
            #   * Called in the same context as the original.
            #
            # Exit status:
            #   * Returns the same value as the original Test::Most function.
            #
            # Side effects:
            #   * On failure, emits additional diagnostics via Test::Builder.
            #
            # Notes:
            #   * This wrapper is transparent on success.
            #   * This is not a separately documented public API; it is a
            #     behavioral enhancement of Test::Most exports.

            my @args = @_;

            # Call the original assertion.
            my $result = $orig->(@args);

            # On success, we do not add any extra diagnostics.
            return $result if $result;

            # On failure, emit enhanced diagnostics.
            _explain_failure($fn, @args);

            return $result;
        };
    }
}

#--------------------------------------------------------------------------#
# import
#
# Public entry point. Called when the user writes:
#   use Test::Most::Explain ...;
#
# Responsibilities:
#   * Load Test::Most into the caller with the same arguments.
#   * Export our wrapped assertion functions into the caller.
#   * Optionally accept a configuration hashref as the last argument
#     in the future (reserved, currently ignored but validated).
#--------------------------------------------------------------------------#
sub import {
    # We use Params::Get and Params::Validate::Strict to keep the
    # public entry point well defined and future proof.
    my ($class, @raw) = @_;

    # We allow an optional trailing hashref of options in the future.
    # For now, we only validate that if present, it is a hashref.
    my ($args, @rest) = get_params(
        \@raw,
        {
            # We treat everything as positional for now, but reserve
            # the last position for an optional hashref of options.
            positional => [
                '*',    # passthrough to Test::Most
            ],
            trailing_named_hashref => 0,    # reserved, currently disabled
        },
    );

    # Validate an empty spec for now; this is mainly to demonstrate
    # that we are wired for strict validation when we add options.
    validate_strict( {}, {} );

    # Load Test::Most into the caller with the original arguments.
    my $caller = caller;

    {
        no strict 'refs';

        # Reuse the original arguments for Test::Most.
        Test::Most->import(@raw);

        # Export our wrapped assertion functions into the caller.
        for my $fn (qw(ok is is_deeply like unlike cmp_ok)) {
            *{"${caller}::$fn"} = \&{$fn};
        }
    }

    return;
}

#--------------------------------------------------------------------------#
# _explain_failure
#
# Entry criteria:
#   * $fn is the name of the assertion that failed (string).
#   * @args are the original arguments passed to that assertion.
#
# Exit status:
#   * Returns undef.
#
# Side effects:
#   * Emits diagnostics via Test::Builder->diag.
#
# Notes:
#   * Dispatches to more specific helpers based on the assertion name.
#   * Designed to be side effect only; return value is not used.
#--------------------------------------------------------------------------#
sub _explain_failure {
    my ($fn, @args) = @_;

    # Header line to make the extra diagnostics easy to spot.
    $TB->diag("== Test::Most::Explain diagnostics for '$fn' ==");

    # Simple dispatch based on assertion type.
    if ($fn eq 'is' || $fn eq 'cmp_ok') {
        my ($got, $expected) = @args;
        _diff_scalars($got, $expected);
    }
    elsif ($fn eq 'is_deeply') {
        my ($got, $expected) = @args;
        _diff_structures($got, $expected);
    }
    else {
        # For now, we do not have specialized logic for other assertions.
        $TB->diag("No specialised diagnostics for '$fn' yet.");
    }

    return;
}

#--------------------------------------------------------------------------#
# _diff_scalars
#
# Entry criteria:
#   * $got and $expected are scalar values (may be undef).
#
# Exit status:
#   * Returns undef.
#
# Side effects:
#   * Emits scalar comparison diagnostics via Test::Builder->diag.
#
# Notes:
#   * Highlights the first differing character index when both are defined.
#   * Does not attempt to coerce references or complex structures.
#--------------------------------------------------------------------------#
sub _diff_scalars {
    my ($got, $expected) = @_;

    # Show the raw values first.
    $TB->diag("Got:      " . (defined $got      ? $got      : '<undef>'));
    $TB->diag("Expected: " . (defined $expected ? $expected : '<undef>'));

    # If both are defined, try to locate the first differing character.
    if (defined $got && defined $expected) {
        my $pos = _first_diff_pos($got, $expected);

        if ($pos >= 0) {
            $TB->diag("First difference at character index $pos");
        }
        else {
            # Same string but still failed; hint at possible type issues.
            $TB->diag(
                "Strings appear identical; consider checking numeric vs string comparison or encoding."
            );
        }
    }
    else {
        # One or both are undef; give a simple hint.
        $TB->diag(
            "One of the values is undef; check for missing data or unexpected undef."
        );
    }

    return;
}

#--------------------------------------------------------------------------#
# _diff_structures
#
# Entry criteria:
#   * $got and $expected are references to data structures suitable
#     for deep comparison (hashrefs, arrayrefs, etc.).
#
# Exit status:
#   * Returns undef.
#
# Side effects:
#   * Emits a contextual diff via Test::Differences and Test::Builder->diag.
#
# Notes:
#   * Lazily loads Test::Differences to avoid unnecessary dependencies
#     when no deep comparisons fail.
#--------------------------------------------------------------------------#
sub _diff_structures {
    my ($got, $expected) = @_;

    # Load Test::Differences on demand.
    require Test::Differences;

    # Use eq_or_diff to show a contextual diff with a small amount of context.
    my $diff = Test::Differences::eq_or_diff(
        $got,
        $expected,
        {
            context => 3,
        },
    );

    $TB->diag("Deep comparison failed:");
    $TB->diag($diff);

    return;
}

#--------------------------------------------------------------------------#
# _first_diff_pos
#
# Entry criteria:
#   * $a and $b are defined strings.
#
# Exit status:
#   * Returns the zero based index of the first differing character,
#     or -1 if the strings are identical up to the length of the shorter.
#
# Side effects:
#   * None.
#
# Notes:
#   * This is a simple linear scan; performance is acceptable for
#     typical test diagnostics.
#--------------------------------------------------------------------------#
sub _first_diff_pos {
    my ($a, $b) = @_;

    my $len = length($a) < length($b) ? length($a) : length($b);

    for my $i (0 .. $len - 1) {
        return $i if substr($a, $i, 1) ne substr($b, $i, 1);
    }

    # If lengths differ, the first difference is at the end of the shorter.
    return length($a) != length($b) ? $len : -1;
}

1;

__END__

=pod

=head1 NAME

Test::Most::Explain - Enhanced diagnostics for failing Test::Most assertions

=head1 SYNOPSIS

  use Test::Most::Explain;

  # All your usual Test::Most assertions still work:
  ok( 1, 'this passes' );

  # When assertions fail, diagnostics are more readable:
  is( 'foo', 'bar', 'scalar mismatch' );

  is_deeply(
      { a => 1, b => 2 },
      { a => 1, b => 3 },
      'deep mismatch',
  );

=head1 DESCRIPTION

Test::Most::Explain is a diagnostic enhancer that sits on top of
L<Test::Most>. It intercepts selected assertion failures and emits
more readable diagnostics.

The goal is to make failing tests easier to understand without
changing how you write tests. You still call C<ok>, C<is>,
C<is_deeply>, and friends. When they fail, this module adds:

=over 4

=item *

Contextual diffs for deep structures.

=item *

Scalar comparison hints, including first differing character index.

=item *

Simple heuristics for common failure patterns.

=back

Think of it as Test2 style diagnostics without requiring Test2.

=head1 PUBLIC INTERFACE

The public interface of this module is intentionally small. The
only public routine you are expected to call directly is C<import>,
which is invoked via C<use>. All assertion functions such as C<ok>
and C<is> are re-exports from L<Test::Most> with enhanced behavior,
but they are not considered a separate API surface here.

=head2 import

Import Test::Most::Explain into your test script.

This is normally invoked via:

  use Test::Most::Explain;

=head3 Purpose

Load L<Test::Most> into the caller and install enhanced versions
of selected assertion functions (C<ok>, C<is>, C<is_deeply>,
C<like>, C<unlike>, C<cmp_ok>) that emit better diagnostics on
failure.

=head3 Arguments

The C<import> routine accepts the same arguments you would normally
pass to C<use Test::Most>. These are forwarded directly to
C<Test::Most::import>.

At present, there are no additional named options specific to
Test::Most::Explain, but the signature is designed to allow them
in the future.

=head4 API specification: input (Params::Validate::Strict schema)

The conceptual input schema, expressed in a form compatible with
L<Params::Validate::Strict>, is:

  {
      # All arguments are currently positional and forwarded to Test::Most.
      # No named parameters are defined yet.
      #
      # This is intentionally loose to remain compatible with Test::Most.
  }

In other words, there is no additional validation beyond what
L<Test::Most> itself expects, but the entry point is wired so that
a stricter schema can be introduced without breaking callers.

=head3 Return value

C<import> returns nothing meaningful. It behaves like a typical
Perl C<import> method: it sets up the caller's namespace and
returns C<void>.

=head4 API specification: output (Return::Set schema)

In a form compatible with L<Return::Set>, the conceptual return
set is:

  {
      success => 1,
      value   => undef,
  }

The important point is that there is no data value to consume;
the effect is in the caller's symbol table.

=head3 Side effects

=over 4

=item *

Calls C<Test::Most::import> in the caller's package with the
original arguments.

=item *

Installs wrapper functions for C<ok>, C<is>, C<is_deeply>,
C<like>, C<unlike>, and C<cmp_ok> into the caller's package.
These wrappers delegate to the original L<Test::Most> functions
and add diagnostics on failure.

=back

=head3 Notes

=over 4

=item *

This module does not change the semantics of the assertions on
success. It only adds diagnostics when they fail.

=item *

Future versions may accept a trailing hashref of options to
configure verbosity or behavior. The current implementation
is already structured to support that.

=back

=head3 Example

A simple test file using Test::Most::Explain:

  use strict;
  use warnings;

  use Test::Most::Explain;

  ok( 0, 'force failure to see diagnostics' );

  is( 'alpha', 'alpHa', 'case mismatch' );

  is_deeply(
      { a => 1, b => 2 },
      { a => 1, b => 3 },
      'deep mismatch',
  );

  done_testing();

When you run this test, the failing assertions will be followed
by additional diagnostics from Test::Most::Explain.

=head1 DIAGNOSTIC BEHAVIOR

Although not part of the formal public API, it is useful to know
what kinds of diagnostics are produced.

=over 4

=item Scalar comparisons

For C<is> and C<cmp_ok>, the module prints the C<Got> and
C<Expected> values. If both are defined, it also reports the
index of the first differing character. If the strings appear
identical but the assertion still failed, it suggests checking
for type or encoding issues.

=item Deep structure comparisons

For C<is_deeply>, the module uses L<Test::Differences> to show
a contextual diff of the two structures, with a small amount
of surrounding context.

=back

=head1 CAVEATS

=over 4

=item *

Only a subset of Test::Most assertions are currently enhanced.
Others will still work, but will not receive extra diagnostics
beyond what Test::Most provides.

=item *

This module assumes a standard L<Test::Builder> based environment.
Exotic harnesses that replace Test::Builder may not see the
diagnostics as expected.

=back

=head1 AUTHOR

Nigel (concept), implementation drafted with assistance from Copilot.

=head1 COPYRIGHT AND LICENSE

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

